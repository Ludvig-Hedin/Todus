import Foundation
import SwiftData

/// Offline-capable task mutation queue.
///
/// The filename is retained for Xcode project compatibility, but transport now uses
/// the unified Better Auth + tRPC backend through `TodosAPIClient`.
@MainActor
final class SupabaseSyncService: SyncService {
    /// Capture rollback is destructive, so only statuses whose contract explicitly
    /// means "this task payload is semantically invalid" belong here. Authentication,
    /// throttling, conflicts, timeouts, and server failures are recoverable and must
    /// keep the local task for retry.
    private static let semanticRejectionStatusCodes: Set<Int> = [422]

    private struct PendingBatch {
        let mutations: [SyncMutation]
        let taskIDs: [UUID]
        let generation: UInt64
        let continuation: CheckedContinuation<Void, Never>
    }

    private struct TaskSyncRequest: Encodable {
        let mutations: [TaskMutation]
    }

    private struct TaskMutation: Encodable {
        let type: String
        let id: String
        let payload: TaskMutationPayload?

        private enum CodingKeys: String, CodingKey {
            case type, id, payload
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(payload, forKey: .payload)
        }
    }

    private struct TaskMutationPayload: Encodable {
        let title: String
        let description: String
        let status: String
        let priority: String
        /// Intentionally a string rather than `Date`: `tasks.sync` validates this
        /// field with `z.string().datetime()`. `TodosAPIClient.trpcMutation` revives
        /// Swift Dates through superjson, which would turn it into a JS Date before
        /// Zod validation and reject an otherwise valid task.
        let dueDate: String?
        let folderId: String?
        let reminderIdentifier: String?
        let emailThreadId: String?
        let eventId: String?
    }

    private struct TaskSyncResponse: Decodable {
        let syncedIds: [String]
    }

    private struct TaskSyncEnvelope: Decodable {
        struct Result: Decodable {
            struct DataValue: Decodable {
                let json: TaskSyncResponse
            }

            let data: DataValue
        }

        let result: Result
    }

    private struct TaskListInput: Encodable {
        let sortBy = "newest"
        let limit: Int
        let offset: Int
    }

    private struct TaskListResponse: Decodable {
        let tasks: [RemoteTask]
    }

    private struct TaskDeletionListInput: Encodable {
        let limit: Int
        let offset: Int
    }

    private struct TaskDeletionListResponse: Decodable {
        let deletions: [RemoteTaskDeletion]
    }

    private struct RemoteTaskDeletion: Decodable {
        let taskId: String
        let deletedAt: Date
    }

    private struct RemoteTask: Decodable {
        let id: String
        let title: String
        let description: String
        let status: String
        let priority: String
        let dueDate: Date?
        let folderId: String?
        let reminderIdentifier: String?
        let emailThreadId: String?
        let eventId: String?
        let createdAt: Date
        let updatedAt: Date
    }

    private let apiClient: TodosAPIClient?
    private let defaults: UserDefaults
    private let pendingDeleteRetriesKey: String
    /// AppServices wires this after reminder and notification dependencies exist.
    /// Called only after the local SwiftData deletion has saved successfully.
    var onRemoteTaskDeleted: ((UUID, String?) -> Void)?
    private var queue: [PendingBatch] = []
    private var isProcessing = false
    /// Generation currently pulling remote tasks. A new account may start its
    /// own pull even while the invalidated previous account request unwinds.
    private var remoteReconcileGeneration: UInt64?
    /// Invalidates an awaited batch when sign-out clears account-scoped state.
    /// A failed request from the old account must never repopulate the durable
    /// delete journal after the next account signs in.
    private var queueGeneration: UInt64 = 0
    /// Deletes need their own durable journal because the local `TaskRecord` is
    /// gone and cannot be reconstructed by `retryUnsyncedTasks`. They are added
    /// before transport starts, so an app kill during the request is also safe.
    private var pendingDeleteRetries: [SyncMutation] = [] {
        didSet { persistPendingDeleteRetries() }
    }

    private static let pendingDeleteRetriesKey = "TaskApp.pendingDeleteRetries"

    init(
        configuration: AppConfiguration,
        authStore: AuthSessionStore,
        apiClient: TodosAPIClient? = nil,
        defaults: UserDefaults = .standard,
        pendingDeleteRetriesKey: String = SupabaseSyncService.pendingDeleteRetriesKey
    ) {
        _ = configuration
        _ = authStore
        self.apiClient = apiClient
        self.defaults = defaults
        self.pendingDeleteRetriesKey = pendingDeleteRetriesKey
        if let data = defaults.data(forKey: pendingDeleteRetriesKey),
           let restored = try? JSONDecoder().decode([SyncMutation].self, from: data) {
            pendingDeleteRetries = Self.deduplicatingDeletes(restored)
        }
    }

    func enqueue(_ mutations: [SyncMutation], in context: ModelContext) async {
        guard !mutations.isEmpty else { return }
        let affectedTaskIDs = Array(Set(mutations.flatMap(\.affectedTaskIDs)))
        recordPendingDeletes(from: mutations)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.append(PendingBatch(
                mutations: mutations,
                taskIDs: affectedTaskIDs,
                generation: queueGeneration,
                continuation: continuation
            ))

            guard apiClient != nil else {
                markTasks(taskIDs: affectedTaskIDs, syncState: .localOnly, in: context)
                queue.removeLast()
                continuation.resume()
                return
            }

            Task { await self.processQueue(in: context) }
        }
    }

    /// Re-enqueues every local task that still needs upload, plus durable delete
    /// tombstones whose records no longer exist locally.
    func retryUnsyncedTasks(in context: ModelContext) async {
        guard apiClient != nil else { return }
        let tasks = (try? context.fetch(FetchDescriptor<TaskRecord>())) ?? []
        let toRetry = tasks.filter {
            $0.syncState == .localOnly
                || $0.syncState == .failed
                || $0.syncState == .pendingUpload
        }
        let deleteRetries = pendingDeleteRetries
        guard !toRetry.isEmpty || !deleteRetries.isEmpty else { return }

        if toRetry.isEmpty {
            await enqueue(deleteRetries, in: context)
            return
        }

        let mutations = deleteRetries + toRetry.map { task in
            SyncMutation(action: .upsert, task: task.asPayload(), taskID: task.id)
        }
        let originalStates: [(TaskRecord, SyncState)] = toRetry.map { ($0, $0.syncState) }
        for task in toRetry {
            task.syncState = .pendingUpload
        }
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

    /// Hydrates tasks changed on another client and applies explicit deletion
    /// tombstones. Local pending work is never deleted by reconciliation; once
    /// the server acknowledges it, a matching tombstone can safely remove it.
    func reconcileRemoteTasks(in context: ModelContext) async {
        let generation = queueGeneration
        guard remoteReconcileGeneration != generation, let apiClient else { return }
        remoteReconcileGeneration = generation
        defer {
            if remoteReconcileGeneration == generation {
                remoteReconcileGeneration = nil
            }
        }

        let pageSize = 200
        let maxPages = 100
        var remoteByID: [UUID: RemoteTask] = [:]
        var deletionByID: [UUID: RemoteTaskDeletion] = [:]

        do {
            for page in 0..<maxPages {
                let response: TaskListResponse = try await apiClient.trpcQuery(
                    "tasks.list",
                    input: TaskListInput(limit: pageSize, offset: page * pageSize)
                )
                guard generation == queueGeneration else { return }

                for remote in response.tasks {
                    guard let id = UUID(uuidString: remote.id) else { continue }
                    if let existing = remoteByID[id], existing.updatedAt >= remote.updatedAt {
                        continue
                    }
                    remoteByID[id] = remote
                }
                if response.tasks.count < pageSize { break }
                if page == maxPages - 1 {
                    AppLogger.shared.log("[TaskSync] tasks.list stopped at \(maxPages * pageSize) rows")
                }
            }

            for page in 0..<maxPages {
                let response: TaskDeletionListResponse = try await apiClient.trpcQuery(
                    "tasks.deleted",
                    input: TaskDeletionListInput(limit: pageSize, offset: page * pageSize)
                )
                guard generation == queueGeneration else { return }

                for deletion in response.deletions {
                    guard let id = UUID(uuidString: deletion.taskId) else { continue }
                    if let existing = deletionByID[id], existing.deletedAt >= deletion.deletedAt {
                        continue
                    }
                    deletionByID[id] = deletion
                }
                if response.deletions.count < pageSize { break }
                if page == maxPages - 1 {
                    AppLogger.shared.log("[TaskSync] tasks.deleted stopped at \(maxPages * pageSize) rows")
                }
            }

            guard generation == queueGeneration else { return }
            applyRemoteState(
                tasks: Array(remoteByID.values),
                deletions: Array(deletionByID.values),
                in: context
            )
        } catch {
            // Offline/auth/server errors leave the complete local cache untouched.
            AppLogger.shared.log("[TaskSync] remote reconciliation failed: \(error.localizedDescription)")
        }
    }

    /// The unified backend already scopes tasks to the Better Auth session, so
    /// there is no anonymous-user edge function to call. Signing in simply
    /// flushes any local work through the authenticated tRPC client.
    func upgradeAnonymousUserIfNeeded(email: String, in context: ModelContext) async {
        guard !email.isEmpty else { return }
        await retryUnsyncedTasks(in: context)
    }

    /// Clears queued and durable account-scoped mutations on sign-out. The
    /// generation check also prevents an old in-flight failure from restoring
    /// tombstones after a different account signs in.
    func clearPendingMutations() {
        queueGeneration &+= 1
        let abandoned = queue
        queue.removeAll()
        pendingDeleteRetries.removeAll()
        persistPendingDeleteRetries()
        for batch in abandoned {
            batch.continuation.resume()
        }
    }

    private func processQueue(in context: ModelContext) async {
        guard !isProcessing, let apiClient else { return }
        isProcessing = true
        defer { isProcessing = false }

        while !queue.isEmpty {
            let batch = queue.removeFirst()
            let wireMutations = makeWireMutations(batch.mutations, in: context)

            do {
                let response = try await send(wireMutations, using: apiClient)
                guard batch.generation == queueGeneration else {
                    batch.continuation.resume()
                    continue
                }

                let syncedIDs = Set(response.syncedIds.compactMap(UUID.init(uuidString:)))
                markTasks(taskIDs: Array(syncedIDs), syncState: .synced, in: context)
                let unacknowledged = batch.taskIDs.filter { !syncedIDs.contains($0) }
                markTasks(taskIDs: unacknowledged, syncState: .localOnly, in: context)
                removePendingDeletes(acknowledgedIDs: syncedIDs)
            } catch {
                guard batch.generation == queueGeneration else {
                    batch.continuation.resume()
                    continue
                }
                AppLogger.shared.log("[TaskSync] tasks.sync failed: \(error.localizedDescription)")
                let keepLocal = Self.isRecoverable(error)
                markTasks(
                    taskIDs: batch.taskIDs,
                    syncState: keepLocal ? .localOnly : .failed,
                    in: context
                )
                if !keepLocal {
                    removePendingDeletes(
                        acknowledgedIDs: Set(batch.mutations.compactMap(\.taskID))
                    )
                }
            }
            batch.continuation.resume()
        }
    }

    private func makeWireMutations(
        _ mutations: [SyncMutation],
        in context: ModelContext
    ) -> [TaskMutation] {
        mutations.compactMap { mutation in
            guard let id = mutation.task?.id ?? mutation.taskID else { return nil }
            guard mutation.action == .upsert, let task = mutation.task else {
                return TaskMutation(type: "delete", id: id.uuidString, payload: nil)
            }

            let record = fetchTask(id: id, in: context)
            return TaskMutation(
                type: "upsert",
                id: id.uuidString,
                payload: TaskMutationPayload(
                    title: task.title,
                    description: task.taskDescription,
                    status: task.status.rawValue,
                    priority: task.priority.rawValue,
                    dueDate: task.dueDate.map(Self.iso8601String),
                    folderId: task.folderID?.uuidString,
                    reminderIdentifier: task.reminderIdentifier,
                    emailThreadId: record?.emailThreadId,
                    eventId: record?.eventId
                )
            )
        }
    }

    private func applyRemoteState(
        tasks remoteTasks: [RemoteTask],
        deletions remoteDeletions: [RemoteTaskDeletion],
        in context: ModelContext
    ) {
        let localTasks = (try? context.fetch(FetchDescriptor<TaskRecord>())) ?? []
        var localByID = Dictionary(uniqueKeysWithValues: localTasks.map { ($0.id, $0) })
        let folders = (try? context.fetch(FetchDescriptor<FolderRecord>())) ?? []
        let foldersByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        let deletedIDs = Set(remoteDeletions.compactMap { UUID(uuidString: $0.taskId) })
        var deletedLocalTasks: [(id: UUID, reminderIdentifier: String?)] = []

        for remote in remoteTasks {
            guard let id = UUID(uuidString: remote.id),
                  !deletedIDs.contains(id),
                  let status = TaskStatus(rawValue: remote.status),
                  let priority = AppTaskPriority(rawValue: remote.priority) else { continue }
            let folder = remote.folderId.flatMap(UUID.init(uuidString:)).flatMap { foldersByID[$0] }

            if let local = localByID[id] {
                guard local.syncState == .synced, remote.updatedAt > local.updatedAt else { continue }
                local.title = remote.title
                local.taskDescription = remote.description
                local.status = status
                local.completedAt = status == .done ? remote.updatedAt : nil
                local.priority = priority
                local.dueDate = remote.dueDate
                local.folder = folder
                local.reminderIdentifier = remote.reminderIdentifier
                local.emailThreadId = remote.emailThreadId
                local.eventId = remote.eventId
                local.createdAt = remote.createdAt
                local.updatedAt = remote.updatedAt
                local.parseState = .parsed
                local.syncState = .synced
            } else {
                let task = TaskRecord(
                    id: id,
                    rawInput: remote.title,
                    title: remote.title,
                    taskDescription: remote.description,
                    completed: status == .done,
                    status: status,
                    priority: priority,
                    attachmentNames: [],
                    reminderIdentifier: remote.reminderIdentifier,
                    createdAt: remote.createdAt,
                    updatedAt: remote.updatedAt,
                    dueDate: remote.dueDate,
                    completedAt: status == .done ? remote.updatedAt : nil,
                    folder: folder,
                    parseState: .parsed,
                    syncState: .synced
                )
                task.emailThreadId = remote.emailThreadId
                task.eventId = remote.eventId
                context.insert(task)
                localByID[id] = task
            }
        }

        for id in deletedIDs {
            guard let local = localByID[id], local.syncState == .synced else { continue }
            deletedLocalTasks.append((id: id, reminderIdentifier: local.reminderIdentifier))
            context.delete(local)
            localByID.removeValue(forKey: id)
        }

        do {
            try context.save()
            for deletion in deletedLocalTasks {
                onRemoteTaskDeleted?(deletion.id, deletion.reminderIdentifier)
            }
        } catch {
            context.rollback()
            AppLogger.shared.log("[TaskSync] failed to save reconciled tasks: \(error)")
        }
    }

    /// Sends a pre-encoded tRPC envelope so `dueDate` stays an ISO string. The
    /// generic superjson helper intentionally revives ISO strings as JS Dates,
    /// while this endpoint's Zod schema requires a string.
    private func send(
        _ mutations: [TaskMutation],
        using apiClient: TodosAPIClient
    ) async throws -> TaskSyncResponse {
        let request = TaskSyncRequest(mutations: mutations)
        let json = try JSONEncoder().encode(request)
        let requestObject = try JSONSerialization.jsonObject(with: json)
        let body = try JSONSerialization.data(withJSONObject: ["json": requestObject])
        let data = try await apiClient.sendRawData(
            path: "api/trpc/tasks.sync",
            method: "POST",
            body: body
        )
        do {
            return try JSONDecoder().decode(TaskSyncEnvelope.self, from: data).result.data.json
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private static func isRecoverable(_ error: Error) -> Bool {
        switch error {
        case is URLError:
            return true
        case APIError.httpError(let statusCode, _):
            return !semanticRejectionStatusCodes.contains(statusCode)
        case APIError.unauthorized, APIError.invalidResponse, APIError.decodingError:
            return true
        default:
            return true
        }
    }

    private static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func fetchTask(id: UUID, in context: ModelContext) -> TaskRecord? {
        var descriptor = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func recordPendingDeletes(from mutations: [SyncMutation]) {
        let merged = pendingDeleteRetries + mutations.filter { $0.action == .delete }
        pendingDeleteRetries = Self.deduplicatingDeletes(merged)
    }

    private func removePendingDeletes(acknowledgedIDs: Set<UUID>) {
        guard !acknowledgedIDs.isEmpty else { return }
        pendingDeleteRetries.removeAll { mutation in
            mutation.taskID.map(acknowledgedIDs.contains) ?? false
        }
    }

    private static func deduplicatingDeletes(_ mutations: [SyncMutation]) -> [SyncMutation] {
        var seen: Set<UUID> = []
        return mutations.filter { mutation in
            guard mutation.action == .delete, let id = mutation.taskID else { return false }
            return seen.insert(id).inserted
        }
    }

    private func persistPendingDeleteRetries() {
        if pendingDeleteRetries.isEmpty {
            defaults.removeObject(forKey: pendingDeleteRetriesKey)
        } else if let data = try? JSONEncoder().encode(pendingDeleteRetries) {
            defaults.set(data, forKey: pendingDeleteRetriesKey)
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
