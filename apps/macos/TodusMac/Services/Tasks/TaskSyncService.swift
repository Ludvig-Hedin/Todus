import Foundation
import SwiftData

/// Queues task create/update/delete mutations and flushes them via tRPC `tasks.sync`.
/// Mutations are batched and sent together; on failure the batch is re-queued and each
/// affected task is marked `.failed` so the UI can surface a retry indicator.
@MainActor
final class TaskSyncService {

    // The server expects { type, id, payload?: { title, status, ... } }.
    // `payload` is omitted for delete mutations.
    private struct TaskPayload: Encodable {
        let title: String?
        let description: String?
        let status: String?
        let priority: String?
        let folderId: String?
        let dueDate: String?  // ISO 8601 — server uses z.string().datetime()
    }

    private struct TaskMutation: Encodable {
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

    private var queue: [TaskMutation] = []
    private var isProcessing = false
    private let apiClient: TodosAPIClient

    /// Per-session retry counter keyed by mutation ID (task UUID string).
    /// Caps retries so a stuck mutation can't pin the queue forever.
    private var retryCounts: [String: Int] = [:]
    private static let maxRetries = 5

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
        let mutation = TaskMutation(type: "delete", id: taskID.uuidString, payload: nil)
        queue.append(mutation)
        await processQueue(in: context)
    }

    /// Re-enqueues all tasks in `pendingUpload` or `failed` state and flushes.
    /// Called on network reconnect so locally-created tasks eventually reach the server.
    func retryUnsyncedTasks(in context: ModelContext) async {
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

    /// Discards any queued mutations that have not yet been sent.
    /// Call on sign-out to prevent a reconnect from replaying the previous user's edits.
    func clearQueue() {
        queue.removeAll()
        retryCounts.removeAll()
    }

    // MARK: - Private

    private func processQueue(in context: ModelContext) async {
        guard !isProcessing, !queue.isEmpty else { return }
        isProcessing = true
        defer { isProcessing = false }

        // Drain the queue. New mutations enqueued while a batch is in flight
        // would otherwise sit until the next enqueue or reconnect.
        while !queue.isEmpty {
            let batch = queue
            queue.removeAll()

            do {
                let output: SyncOutput = try await apiClient.trpcMutation(
                    "tasks.sync",
                    input: SyncInput(mutations: batch)
                )
                for idStr in output.syncedIds {
                    guard let uuid = UUID(uuidString: idStr) else { continue }
                    let desc = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == uuid })
                    if let task = try? context.fetch(desc).first {
                        task.syncStateRawValue = SyncState.synced.rawValue
                    }
                    // Clear retry counter for anything the server confirmed.
                    retryCounts.removeValue(forKey: idStr)
                }
                try? context.save()
            } catch {
                // Classify the failure: 4xx → drop (client-side validation issue,
                // retrying won't help). Anything else (network, 5xx, decoding) →
                // requeue with a max-retry cap so a stuck mutation can't pin the
                // queue forever and burn battery in a hot loop.
                let isClientError: Bool = {
                    if case let APIError.httpError(statusCode, _) = error,
                       (400..<500).contains(statusCode) {
                        return true
                    }
                    return false
                }()

                if isClientError {
                    AppLogger.shared.log(
                        "[TaskSyncService] dropping batch of \(batch.count) mutation(s) due to client error: \(error.localizedDescription)"
                    )
                    for mutation in batch {
                        retryCounts.removeValue(forKey: mutation.id)
                        guard let uuid = UUID(uuidString: mutation.id) else { continue }
                        let desc = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == uuid })
                        if let task = try? context.fetch(desc).first {
                            task.syncStateRawValue = SyncState.failed.rawValue
                        }
                    }
                    try? context.save()
                    break
                }

                // Network / 5xx — partition into "still retryable" and "exhausted".
                var retryable: [TaskMutation] = []
                for mutation in batch {
                    let next = (retryCounts[mutation.id] ?? 0) + 1
                    retryCounts[mutation.id] = next
                    if next > Self.maxRetries {
                        AppLogger.shared.log(
                            "[TaskSyncService] dropping mutation \(mutation.id) after \(Self.maxRetries) failed attempts: \(error.localizedDescription)"
                        )
                        retryCounts.removeValue(forKey: mutation.id)
                        if let uuid = UUID(uuidString: mutation.id) {
                            let desc = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == uuid })
                            if let task = try? context.fetch(desc).first {
                                task.syncStateRawValue = SyncState.failed.rawValue
                            }
                        }
                    } else {
                        retryable.append(mutation)
                        if let uuid = UUID(uuidString: mutation.id) {
                            let desc = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == uuid })
                            if let task = try? context.fetch(desc).first {
                                task.syncStateRawValue = SyncState.failed.rawValue
                            }
                        }
                    }
                }
                // Re-queue only mutations that haven't exceeded the retry cap.
                if !retryable.isEmpty {
                    queue.insert(contentsOf: retryable, at: 0)
                }
                try? context.save()
                break
            }
        }
    }
}
