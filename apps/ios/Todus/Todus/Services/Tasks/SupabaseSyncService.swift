import Foundation
import SwiftData

@MainActor
final class SupabaseSyncService: SyncService {
    private struct PendingBatch {
        let mutations: [SyncMutation]
        let taskIDs: [UUID]
        // Resumed when this specific batch finishes processing (success or
        // failure) so callers of enqueue() can await their batch's outcome —
        // not merely "the queue is non-busy".
        let continuation: CheckedContinuation<Void, Never>
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

        // Track this batch via a continuation so callers can await its actual
        // completion — not just "some batch is processing". Without this, a
        // second enqueue() while another batch is in flight returned
        // immediately, causing the rollback path to see `.pendingUpload`
        // instead of `.failed` and silently skip rollback (#22).
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.append(PendingBatch(
                mutations: mutations,
                taskIDs: affectedTaskIDs,
                continuation: continuation
            ))

            if client == nil {
                markTasks(taskIDs: affectedTaskIDs, syncState: .localOnly, in: context)
                // No remote backend to drain against — remove the batch we just
                // appended and resume the caller's continuation exactly once.
                // The previous pop-then-resume pattern double-resumed the same
                // continuation (the popped batch IS the outer one), tripping
                // CheckedContinuation's fatal-error guard.
                queue.removeLast()
                continuation.resume()
                return
            }

            // Kick off processing. processQueue() resumes each batch's
            // continuation as it finishes that batch.
            Task { await self.processQueue(in: context) }
        }
    }

    /// Re-enqueues every task currently in `.localOnly` or `.failed` state for another upload
    /// attempt. Intended to be called when network connectivity is restored, so offline tasks
    /// don't sit forever waiting for the next manual mutation to flush them.
    ///
    /// TODO: Wire this to fire on `NetworkMonitor.isConnected` false→true transitions in
    /// `AppServices`. The infrastructure exists (`apps/ios/Todus/Todus/Services/NetworkMonitor.swift`),
    /// but observation must be set up at the AppServices level since this service has no
    /// reference to it.
    func retryUnsyncedTasks(in context: ModelContext) async {
        guard client != nil else { return }
        let descriptor = FetchDescriptor<TaskRecord>()
        let tasks = (try? context.fetch(descriptor)) ?? []
        // Include `.pendingUpload` so tasks that were mid-flight when the app
        // was killed (e.g. background-suspend → kill before the await returned)
        // get retried. The in-memory queue doesn't survive a kill, so without
        // this they'd stay stranded in pendingUpload forever — never picked up
        // by either the queue or this retry pass.
        let toRetry = tasks.filter {
            $0.syncState == .localOnly
                || $0.syncState == .failed
                || $0.syncState == .pendingUpload
        }
        guard !toRetry.isEmpty else { return }

        let mutations = toRetry.map { task in
            SyncMutation(action: .upsert, task: task.asPayload(), taskID: task.id)
        }
        // Capture each task's pre-retry state so we can restore it verbatim if the
        // optimistic save fails. Without this snapshot, a `.failed` task would be
        // rolled back to `.localOnly` since the bulk transition to `.pendingUpload`
        // erases the original state.
        let originalStates: [(TaskRecord, SyncState)] = toRetry.map { ($0, $0.syncState) }
        for task in toRetry {
            task.syncState = .pendingUpload
        }
        // If we can't persist the optimistic state transition, don't fire mutations
        // that would later show as duplicates against tasks the disk still believes
        // are .localOnly / .failed.
        do {
            try context.save()
        } catch {
            for (task, original) in originalStates {
                task.syncState = original
            }
            return
        }

        await enqueue(mutations, in: context)
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
            batch.continuation.resume()
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
