import Foundation
import SwiftData

/// Queues task create/update/delete mutations and flushes them via tRPC `tasks.sync`.
/// Mutations are batched and sent together; on failure the batch is re-queued and each
/// affected task is marked `.failed` so the UI can surface a retry indicator.
@MainActor
final class TaskSyncService {

    private struct TaskMutationPayload: Encodable {
        let type: String
        let id: String
        let title: String?
        let description: String?
        let status: String?
        let priority: String?
        let folderId: String?
        let dueDate: Date?
    }

    private struct SyncInput: Encodable {
        let mutations: [TaskMutationPayload]
    }

    private struct SyncOutput: Decodable {
        let syncedIds: [String]
    }

    private var queue: [TaskMutationPayload] = []
    private var isProcessing = false
    private let apiClient: TodosAPIClient

    init(apiClient: TodosAPIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Public API

    /// Marks `task` as pending upload, enqueues an upsert mutation, and flushes the queue.
    func enqueueUpsert(_ task: TaskRecord, in context: ModelContext) async {
        task.syncStateRawValue = SyncState.pendingUpload.rawValue
        try? context.save()
        let payload = TaskMutationPayload(
            type: "upsert",
            id: task.id.uuidString,
            title: task.title,
            description: task.taskDescription,
            status: task.statusRawValue,
            priority: task.priorityRawValue,
            folderId: task.folder?.id.uuidString,
            dueDate: task.dueDate
        )
        queue.append(payload)
        await processQueue(in: context)
    }

    /// Enqueues a delete mutation for the given task ID and flushes the queue.
    func enqueueDelete(taskID: UUID, in context: ModelContext) async {
        let payload = TaskMutationPayload(
            type: "delete",
            id: taskID.uuidString,
            title: nil,
            description: nil,
            status: nil,
            priority: nil,
            folderId: nil,
            dueDate: nil
        )
        queue.append(payload)
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
        let payloads = tasks.map { task in
            TaskMutationPayload(
                type: "upsert",
                id: task.id.uuidString,
                title: task.title,
                description: task.taskDescription,
                status: task.statusRawValue,
                priority: task.priorityRawValue,
                folderId: task.folder?.id.uuidString,
                dueDate: task.dueDate
            )
        }
        queue.append(contentsOf: payloads)
        await processQueue(in: context)
    }

    // MARK: - Private

    private func processQueue(in context: ModelContext) async {
        guard !isProcessing, !queue.isEmpty else { return }
        isProcessing = true
        defer { isProcessing = false }

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
            for payload in batch {
                guard let uuid = UUID(uuidString: payload.id) else { continue }
                let desc = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == uuid })
                if let task = try? context.fetch(desc).first {
                    task.syncStateRawValue = SyncState.failed.rawValue
                }
            }
            try? context.save()
        }
    }
}
