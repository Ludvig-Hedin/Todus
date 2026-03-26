import Foundation
import SwiftData

@MainActor
final class SupabaseSyncService: SyncService {
    private struct PendingBatch {
        let mutations: [SyncMutation]
        let taskIDs: [UUID]
    }

    private let configuration: AppConfiguration
    private let authStore: AuthSessionStore
    private let client: SupabaseEdgeFunctionClient?
    private var queue: [PendingBatch] = []
    private var isProcessing = false

    init(configuration: AppConfiguration, authStore: AuthSessionStore) {
        self.configuration = configuration
        self.authStore = authStore
        self.client = configuration.hasRemoteBackend ? SupabaseEdgeFunctionClient(configuration: configuration) : nil
    }

    func enqueue(_ mutations: [SyncMutation], in context: ModelContext) async {
        let affectedTaskIDs = Array(Set(mutations.flatMap(\.affectedTaskIDs)))
        queue.append(PendingBatch(mutations: mutations, taskIDs: affectedTaskIDs))

        if client == nil {
            markTasks(taskIDs: affectedTaskIDs, syncState: .localOnly, in: context)
            return
        }

        await processQueue(in: context)
    }

    func upgradeAnonymousUserIfNeeded(email: String, in context: ModelContext) async {
        guard let client, !email.isEmpty else {
            return
        }

        let request = UpgradeAnonymousUserRequest(
            anonymousID: authStore.anonymousID,
            authenticatedUserID: email
        )

        do {
            let _: EmptyResponse = try await client.invoke(
                path: configuration.upgradeFunctionPath,
                body: request
            )

            let descriptor = FetchDescriptor<TaskRecord>()
            let tasks = (try? context.fetch(descriptor)) ?? []
            for task in tasks where task.syncState == .localOnly || task.syncState == .failed {
                task.syncState = .pendingUpload
            }
            try? context.save()
        } catch {
            return
        }
    }

    private func processQueue(in context: ModelContext) async {
        guard !isProcessing else { return }
        guard let client else { return }
        isProcessing = true

        defer {
            isProcessing = false
        }

        while !queue.isEmpty {
            let batch = queue.removeFirst()
            let request = SyncTasksRequest(
                installID: authStore.installID,
                userID: authStore.currentUserID,
                mutations: batch.mutations
            )

            do {
                let response: SyncTasksResponse = try await client.invoke(
                    path: configuration.syncFunctionPath,
                    body: request
                )
                markTasks(taskIDs: response.syncedTaskIDs, syncState: .synced, in: context)
            } catch {
                markTasks(taskIDs: batch.taskIDs, syncState: .failed, in: context)
            }
        }
    }

    private func markTasks(taskIDs: [UUID], syncState: SyncState, in context: ModelContext) {
        guard !taskIDs.isEmpty else { return }
        let descriptor = FetchDescriptor<TaskRecord>(
            predicate: #Predicate { task in
                taskIDs.contains(task.id)
            }
        )
        let tasks = (try? context.fetch(descriptor)) ?? []
        for task in tasks {
            task.syncState = syncState
            task.updatedAt = .now
        }
        try? context.save()
    }
}
