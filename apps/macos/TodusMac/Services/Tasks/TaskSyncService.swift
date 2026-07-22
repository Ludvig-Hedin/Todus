import Foundation
import SwiftData

/// Queues task create/update/delete mutations and flushes them via tRPC `tasks.sync`.
/// Mutations are batched and sent together; on failure the batch is re-queued and each
/// affected task is marked `.failed` so the UI can surface a retry indicator.
@MainActor
final class TaskSyncService {

    // The server expects { type, id, payload?: { title, status, ... } }.
    // `payload` is omitted for delete mutations.
    private struct TaskPayload: Codable {
        let title: String?
        let description: String?
        let status: String?
        let priority: String?
        let folderId: String?
        let dueDate: String?  // ISO 8601 — server uses z.string().datetime()
    }

    private struct TaskMutation: Codable {
        let type: String
        let id: String
        let payload: TaskPayload?
    }

    private struct SyncInput: Encodable {
        let mutations: [TaskMutation]
    }

    private struct SyncOutput: Decodable {
        let syncedIds: [String]
    }

    private var queue: [TaskMutation] = [] {
        didSet { persistQueue() }
    }
    private var inFlightBatch: [TaskMutation] = []
    private var processingGeneration: Int?
    private let apiClient: TodosAPIClient
    private var activeQueueKey: String?
    private var scopeGeneration = 0
    private var isChangingScope = false
    private static let legacyQueueKey = "TodusMac.taskMutationQueue"

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init(apiClient: TodosAPIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Public API

    /// Marks `task` as pending upload, enqueues an upsert mutation, and flushes the queue.
    func enqueueUpsert(_ task: TaskRecord, in context: ModelContext) async {
        guard activeQueueKey != nil else { return }
        task.syncStateRawValue = SyncState.pendingUpload.rawValue
        try? context.save()
        let mutation = TaskMutation(
            type: "upsert",
            id: task.id.uuidString,
            payload: TaskPayload(
                title: task.title,
                description: task.taskDescription,
                status: task.statusRawValue,
                priority: task.priorityRawValue,
                folderId: task.folder?.id.uuidString,
                dueDate: task.dueDate.map { Self.iso8601.string(from: $0) }
            )
        )
        queue.append(mutation)
        await processQueue(in: context)
    }

    /// Enqueues a delete mutation for the given task ID and flushes the queue.
    func enqueueDelete(taskID: UUID, in context: ModelContext) async {
        guard activeQueueKey != nil else { return }
        let mutation = TaskMutation(type: "delete", id: taskID.uuidString, payload: nil)
        queue.append(mutation)
        await processQueue(in: context)
    }

    /// Re-enqueues all tasks in `pendingUpload` or `failed` state and flushes.
    /// Called on network reconnect so locally-created tasks eventually reach the server.
    func retryUnsyncedTasks(in context: ModelContext) async {
        guard activeQueueKey != nil else { return }
        // Replay persisted tombstones before rebuilding upserts from SwiftData.
        // Deleted rows no longer exist locally, so this queue is their only source.
        if !queue.isEmpty {
            await processQueue(in: context)
            if !queue.isEmpty { return }
        }

        // Fetch all, then filter in memory. A compound `||` string-equality
        // `#Predicate` traps inside SwiftData here (EXC_BREAKPOINT on fetch),
        // and this now runs on every launch/foreground via `flushPendingSync`,
        // so the predicate form crashed the app at startup.
        let descriptor = FetchDescriptor<TaskRecord>()
        let tasks = ((try? context.fetch(descriptor)) ?? []).filter {
            $0.syncStateRawValue == "pendingUpload" || $0.syncStateRawValue == "failed"
        }
        guard !tasks.isEmpty else { return }
        let mutations = tasks.map { task in
            TaskMutation(
                type: "upsert",
                id: task.id.uuidString,
                payload: TaskPayload(
                    title: task.title,
                    description: task.taskDescription,
                    status: task.statusRawValue,
                    priority: task.priorityRawValue,
                    folderId: task.folder?.id.uuidString,
                    dueDate: task.dueDate.map { Self.iso8601.string(from: $0) }
                )
            )
        }
        queue.append(contentsOf: mutations)
        await processQueue(in: context)
    }

    /// Discards the active account's queued mutations. Account switching uses
    /// `deactivateScope()` so normal sign-out never destroys pending work.
    func clearQueue() {
        scopeGeneration += 1
        inFlightBatch.removeAll()
        queue.removeAll()
    }

    /// Switches the durable mutation journal to the authenticated account.
    /// The legacy unscoped journal stays quarantined because it has no trustworthy owner.
    func activateScope(_ scopeID: String) {
        let nextKey = "\(Self.legacyQueueKey).\(scopeID)"
        guard activeQueueKey != nextKey else { return }

        scopeGeneration += 1
        persistQueue()
        isChangingScope = true
        inFlightBatch.removeAll()
        queue.removeAll()
        activeQueueKey = nextKey

        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: nextKey),
           let restored = try? JSONDecoder().decode([TaskMutation].self, from: data) {
            queue = restored
        }
        isChangingScope = false
        persistQueue()
    }

    /// Stops the signed-out app from flushing an account journal while keeping
    /// every pending mutation durable for the next login to that account.
    func deactivateScope() {
        scopeGeneration += 1
        persistQueue()
        isChangingScope = true
        inFlightBatch.removeAll()
        queue.removeAll()
        activeQueueKey = nil
        isChangingScope = false
        processingGeneration = nil
    }

    // MARK: - Private

    private func processQueue(in context: ModelContext) async {
        let processGeneration = scopeGeneration
        guard activeQueueKey != nil,
              processingGeneration != processGeneration,
              !queue.isEmpty else { return }
        processingGeneration = processGeneration
        defer {
            if processingGeneration == processGeneration {
                processingGeneration = nil
            }
        }

        // Drain the queue. New mutations enqueued while a batch is in flight
        // would otherwise sit until the next enqueue or reconnect.
        while !queue.isEmpty {
            let batch = queue
            let batchGeneration = scopeGeneration
            inFlightBatch = batch
            queue.removeAll()

            do {
                let output: SyncOutput = try await apiClient.trpcMutation(
                    "tasks.sync",
                    input: SyncInput(mutations: batch)
                )
                guard batchGeneration == scopeGeneration, activeQueueKey != nil else { return }
                let syncedIDs = Set(output.syncedIds)
                for idStr in syncedIDs {
                    guard let uuid = UUID(uuidString: idStr) else { continue }
                    let desc = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == uuid })
                    if let task = try? context.fetch(desc).first {
                        task.syncStateRawValue = SyncState.synced.rawValue
                    }
                }
                try? context.save()

                let unacknowledged = batch.filter { !syncedIDs.contains($0.id) }
                inFlightBatch.removeAll()
                if !unacknowledged.isEmpty {
                    queue.insert(contentsOf: unacknowledged, at: 0)
                    break
                }
                persistQueue()
            } catch {
                guard batchGeneration == scopeGeneration, activeQueueKey != nil else { return }
                // Only the backend's explicit semantic validation response is
                // permanent. Auth/config/conflict failures may recover and must
                // not discard edits or delete tombstones.
                let isClientError: Bool = {
                    if case let APIError.httpError(statusCode, _) = error { return statusCode == 422 }
                    return false
                }()

                if isClientError {
                    AppLogger.shared.log(
                        "[TaskSyncService] dropping batch of \(batch.count) mutation(s) due to client error: \(error.localizedDescription)"
                    )
                    for mutation in batch {
                        guard let uuid = UUID(uuidString: mutation.id) else { continue }
                        let desc = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == uuid })
                        if let task = try? context.fetch(desc).first {
                            task.syncStateRawValue = SyncState.failed.rawValue
                        }
                    }
                    inFlightBatch.removeAll()
                    persistQueue()
                    try? context.save()
                    break
                }

                // Network / 5xx / decoding failures stay queued until the
                // server acknowledges them. A retry cap loses delete tombstones
                // and allows the server copy to resurrect on the next refresh.
                for mutation in batch {
                    if let uuid = UUID(uuidString: mutation.id) {
                        let desc = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == uuid })
                        if let task = try? context.fetch(desc).first {
                            task.syncStateRawValue = SyncState.failed.rawValue
                        }
                    }
                }
                inFlightBatch.removeAll()
                queue.insert(contentsOf: batch, at: 0)
                try? context.save()
                break
            }
        }
    }

    private func persistQueue() {
        guard !isChangingScope, let activeQueueKey else { return }
        let pending = inFlightBatch + queue
        if pending.isEmpty {
            UserDefaults.standard.removeObject(forKey: activeQueueKey)
        } else if let data = try? JSONEncoder().encode(pending) {
            UserDefaults.standard.set(data, forKey: activeQueueKey)
        }
    }
}
