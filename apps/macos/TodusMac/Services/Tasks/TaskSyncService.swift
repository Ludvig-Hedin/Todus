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
        let descriptor = FetchDescriptor<TaskRecord>(
            predicate: #Predicate {
                $0.syncStateRawValue == "pendingUpload" || $0.syncStateRawValue == "failed"
            }
        )
        let tasks = (try? context.fetch(descriptor)) ?? []
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
                }
                try? context.save()
            } catch {
                // Re-queue the batch so it will be retried on the next call or reconnect.
                queue.insert(contentsOf: batch, at: 0)
                for mutation in batch {
                    guard let uuid = UUID(uuidString: mutation.id) else { continue }
                    let desc = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == uuid })
                    if let task = try? context.fetch(desc).first {
                        task.syncStateRawValue = SyncState.failed.rawValue
                    }
                }
                try? context.save()
                break
            }
        }
    }
}
