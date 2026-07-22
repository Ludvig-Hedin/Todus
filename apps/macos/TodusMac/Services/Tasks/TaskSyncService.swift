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
    private var processingTask: Task<Void, Never>?
    private let apiClient: TodosAPIClient
    private var activeQueueKey: String?
    private var scopeGeneration = 0
    private var isChangingScope = false
    private var queueKeysByContainerID: [ObjectIdentifier: String] = [:]
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
        guard let targetQueueKey = queueKey(for: context) else { return }
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
        guard targetQueueKey == activeQueueKey else {
            appendToDeferredJournal(mutation, queueKey: targetQueueKey)
            return
        }
        queue.append(mutation)
        await processQueue(in: context)
    }

    /// Enqueues a delete mutation for the given task ID and flushes the queue.
    func enqueueDelete(taskID: UUID, in context: ModelContext) async {
        guard let targetQueueKey = queueKey(for: context) else { return }
        let mutation = TaskMutation(type: "delete", id: taskID.uuidString, payload: nil)
        guard targetQueueKey == activeQueueKey else {
            appendToDeferredJournal(mutation, queueKey: targetQueueKey)
            return
        }
        queue.append(mutation)
        await processQueue(in: context)
    }

    /// Re-enqueues all tasks in `pendingUpload` or `failed` state and flushes.
    /// Called on network reconnect so locally-created tasks eventually reach the server.
    func retryUnsyncedTasks(in context: ModelContext) async {
        guard queueKey(for: context) == activeQueueKey, activeQueueKey != nil else { return }
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
    @discardableResult
    func activateScope(_ scopeID: String, context: ModelContext) -> Bool {
        let nextKey = "\(Self.legacyQueueKey).\(scopeID)"
        queueKeysByContainerID[ObjectIdentifier(context.container)] = nextKey
        guard activeQueueKey != nextKey else { return true }

        scopeGeneration += 1
        persistQueue()
        processingTask?.cancel()
        processingTask = nil
        processingGeneration = nil
        isChangingScope = true
        inFlightBatch.removeAll()
        queue.removeAll()

        let defaults = UserDefaults.standard
        let deferredKey = deferredQueueKey(for: nextKey)
        guard let restored = decodeJournal(forKey: nextKey, defaults: defaults),
              let deferred = decodeJournal(forKey: deferredKey, defaults: defaults) else {
            activeQueueKey = nil
            isChangingScope = false
            return false
        }
        activeQueueKey = nextKey
        queue = restored + deferred
        isChangingScope = false
        persistQueue()
        defaults.removeObject(forKey: deferredKey)
        return true
    }

    /// Stops the signed-out app from flushing an account journal while keeping
    /// every pending mutation durable for the next login to that account.
    func deactivateScope() {
        scopeGeneration += 1
        persistQueue()
        processingTask?.cancel()
        isChangingScope = true
        inFlightBatch.removeAll()
        queue.removeAll()
        activeQueueKey = nil
        isChangingScope = false
        processingTask = nil
        processingGeneration = nil
    }

    // MARK: - Private

    private func processQueue(in context: ModelContext) async {
        let processGeneration = scopeGeneration
        guard let processQueueKey = activeQueueKey,
              queueKey(for: context) == processQueueKey,
              !queue.isEmpty else { return }

        if processingGeneration == processGeneration, let processingTask {
            await processingTask.value
            return
        }

        processingGeneration = processGeneration
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.drainQueue(
                in: context,
                generation: processGeneration,
                queueKey: processQueueKey
            )
        }
        processingTask = task
        await task.value
        if processingGeneration == processGeneration {
            processingTask = nil
            processingGeneration = nil
        }
    }

    private func drainQueue(
        in context: ModelContext,
        generation processGeneration: Int,
        queueKey processQueueKey: String
    ) async {
        defer {
            if processingGeneration == processGeneration {
                inFlightBatch.removeAll()
            }
        }

        // Drain the queue. New mutations enqueued while a batch is in flight
        // would otherwise sit until the next enqueue or reconnect.
        while !queue.isEmpty {
            guard !Task.isCancelled,
                  scopeGeneration == processGeneration,
                  activeQueueKey == processQueueKey else { return }
            let batch = queue
            inFlightBatch = batch
            queue.removeAll()

            do {
                let output: SyncOutput = try await apiClient.trpcMutation(
                    "tasks.sync",
                    input: SyncInput(mutations: batch)
                )
                guard !Task.isCancelled,
                      processGeneration == scopeGeneration,
                      activeQueueKey == processQueueKey else { return }
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
                guard !Task.isCancelled,
                      processGeneration == scopeGeneration,
                      activeQueueKey == processQueueKey else { return }
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

    private func queueKey(for context: ModelContext) -> String? {
        queueKeysByContainerID[ObjectIdentifier(context.container)]
    }

    private func deferredQueueKey(for queueKey: String) -> String {
        "\(queueKey).deferred"
    }

    private func decodeJournal(
        forKey key: String,
        defaults: UserDefaults
    ) -> [TaskMutation]? {
        guard let data = defaults.data(forKey: key) else { return [] }
        guard let mutations = try? JSONDecoder().decode([TaskMutation].self, from: data) else {
            AppLogger.shared.log("[TaskSyncService] Refusing to overwrite unreadable journal \(key)")
            return nil
        }
        return mutations
    }

    private func appendToDeferredJournal(_ mutation: TaskMutation, queueKey: String) {
        let defaults = UserDefaults.standard
        let key = deferredQueueKey(for: queueKey)
        guard var pending = decodeJournal(forKey: key, defaults: defaults) else { return }
        pending.append(mutation)
        if let data = try? JSONEncoder().encode(pending) {
            defaults.set(data, forKey: key)
        }
    }
}
