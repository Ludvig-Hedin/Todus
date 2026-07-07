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
    /// Delete mutations that failed on a *network* error. Deletions remove the
    /// local TaskRecord immediately, so unlike upserts they can't be rebuilt from
    /// surviving records by `retryUnsyncedTasks` — dropping the batch lost the
    /// deletion forever and the task resurrected from the server on next pull.
    /// Deduped by taskID, replayed on the next retry pass, and persisted to
    /// UserDefaults (SyncMutation is Codable) so an app kill before reconnect
    /// doesn't lose the deletion either.
    private var pendingDeleteRetries: [SyncMutation] = [] {
        didSet { persistPendingDeleteRetries() }
    }

    private static let pendingDeleteRetriesKey = "TaskApp.pendingDeleteRetries"

    init(configuration: AppConfiguration, authStore: AuthSessionStore) {
        self.configuration = configuration
        self.authStore = authStore
        self.client = configuration.hasRemoteBackend ? SupabaseEdgeFunctionClient(configuration: configuration) : nil
        // Restore delete tombstones from a previous run (offline delete → kill).
        if let data = UserDefaults.standard.data(forKey: Self.pendingDeleteRetriesKey),
           let restored = try? JSONDecoder().decode([SyncMutation].self, from: data) {
            pendingDeleteRetries = restored
        }
    }

    private func persistPendingDeleteRetries() {
        if pendingDeleteRetries.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.pendingDeleteRetriesKey)
        } else if let data = try? JSONEncoder().encode(pendingDeleteRetries) {
            UserDefaults.standard.set(data, forKey: Self.pendingDeleteRetriesKey)
        }
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
    /// attempt. Called when network connectivity is restored — wired in `AppServices` via
    /// `NetworkMonitor.onReconnect` — so offline tasks don't sit forever waiting for the next
    /// manual mutation to flush them.
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
        // Deletions kept from network-failed batches — their records are gone
        // locally, so they must be replayed verbatim or the server resurrects
        // the task on the next pull. Drain even when there are no upsert retries.
        let deleteRetries = pendingDeleteRetries
        pendingDeleteRetries = []
        guard !toRetry.isEmpty || !deleteRetries.isEmpty else { return }
        if toRetry.isEmpty {
            await enqueue(deleteRetries, in: context)
            return
        }

        let mutations = deleteRetries + toRetry.map { task in
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
                // `TaskCaptureService` rolls back (DELETES) `.failed` tasks, so we
                // must only mark `.failed` when the server actively rejected the
                // batch — never when we simply couldn't reach it, or it would
                // delete a task the user captured while offline. Keep those
                // `.localOnly` so they stay in the list and re-upload on reconnect
                // via `retryUnsyncedTasks` (wired through `NetworkMonitor.onReconnect`).
                let keepLocal: Bool
                switch error {
                case is URLError:
                    // Offline / timeout / DNS / cannot-connect.
                    keepLocal = true
                case BackendClientError.backendNotConfigured:
                    // No usable Supabase endpoint — same as the no-remote-backend
                    // path; the task has nowhere to sync, so keep it, don't delete.
                    keepLocal = true
                default:
                    // Server reached and rejected (non-2xx / bad payload) — the
                    // case the rollback was designed for.
                    keepLocal = false
                }
                markTasks(
                    taskIDs: batch.taskIDs,
                    syncState: keepLocal ? .localOnly : .failed,
                    in: context
                )
                if keepLocal {
                    // Preserve the batch's delete mutations for the reconnect
                    // retry — their local records are already gone, so nothing
                    // else can regenerate them (FolderSyncService requeues its
                    // whole batch for the same reason).
                    let deletes = batch.mutations.filter { $0.action == .delete }
                    let alreadyPending = Set(pendingDeleteRetries.map(\.taskID))
                    pendingDeleteRetries.append(contentsOf: deletes.filter { !alreadyPending.contains($0.taskID) })
                }
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
