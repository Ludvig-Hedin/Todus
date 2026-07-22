import Foundation
import SwiftData

/// Offline-capable queue for folder create/update/delete mutations.
/// Mutations are enqueued immediately and flushed via the tRPC `folders.sync` endpoint
/// when online. On network failure the batch is requeued and retried on reconnect.
@MainActor
final class FolderSyncService {

    // MARK: - Mutation types

    enum Mutation: Codable {
        case upsert(id: String, name: String, color: String?, icon: String?, position: Int)
        case delete(id: String)

        var folderID: String {
            switch self {
            case .upsert(let id, _, _, _, _), .delete(let id): id
            }
        }
    }

    // MARK: - Wire types

    /// Single payload struct that covers both upsert and delete variants.
    /// Optional fields are omitted from JSON when nil, matching the server's expectations.
    private struct FolderMutationPayload: Encodable {
        let type: String
        let id: String
        let name: String?
        let color: String?
        let icon: String?
        let position: Int?
    }

    private struct FolderSyncRequest: Encodable {
        let mutations: [FolderMutationPayload]
    }

    private struct FolderSyncResponse: Decodable {
        let syncedIds: [String]
    }

    // MARK: - State

    private var queue: [Mutation] = [] {
        didSet { persistQueue() }
    }
    private var inFlightIDs: Set<String> = []
    private var inFlightBatch: [Mutation] = []
    private var processingGeneration: Int?
    private var processingTask: Task<Void, Never>?
    private let apiClient: TodosAPIClient
    private var activeQueueKey: String?
    private var scopeGeneration = 0
    private var isChangingScope = false
    private var queueKeysByContainerID: [ObjectIdentifier: String] = [:]
    private static let legacyQueueKey = "TodusMac.folderMutationQueue"

    // MARK: - Init

    init(apiClient: TodosAPIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Public API

    /// Append a mutation to the queue and immediately attempt to flush.
    func enqueue(_ mutation: Mutation, in context: ModelContext) async {
        guard let targetQueueKey = queueKey(for: context) else { return }
        guard targetQueueKey == activeQueueKey else {
            appendToDeferredJournal(mutation, queueKey: targetQueueKey)
            return
        }
        queue.append(mutation)
        await processQueue()
    }

    /// Re-attempt any pending mutations — call this on network reconnect.
    func retryPending(in context: ModelContext) async {
        guard queueKey(for: context) == activeQueueKey, activeQueueKey != nil else { return }
        await processQueue()
    }

    /// Discards the active account's queued mutations. Account switching uses
    /// `deactivateScope()` so normal sign-out never destroys pending work.
    func clearQueue() {
        scopeGeneration += 1
        inFlightBatch.removeAll()
        queue.removeAll()
    }

    /// Switches to an account-owned journal. The legacy unscoped journal stays
    /// quarantined because automatically assigning it could cross an account boundary.
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
        inFlightIDs.removeAll()
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

    func deactivateScope() {
        scopeGeneration += 1
        persistQueue()
        processingTask?.cancel()
        isChangingScope = true
        inFlightBatch.removeAll()
        inFlightIDs.removeAll()
        queue.removeAll()
        activeQueueKey = nil
        isChangingScope = false
        processingTask = nil
        processingGeneration = nil
    }

    /// Prevent server refreshes from reverting a local mutation while it is
    /// queued or awaiting acknowledgement.
    func hasPending(id: String) -> Bool {
        inFlightIDs.contains(id) || queue.contains { $0.folderID == id }
    }

    // MARK: - Private

    private func processQueue() async {
        let processGeneration = scopeGeneration
        guard let processQueueKey = activeQueueKey,
              !queue.isEmpty else { return }

        if processingGeneration == processGeneration, let processingTask {
            await processingTask.value
            return
        }

        processingGeneration = processGeneration
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.drainQueue(generation: processGeneration, queueKey: processQueueKey)
        }
        processingTask = task
        await task.value
        if processingGeneration == processGeneration {
            processingTask = nil
            processingGeneration = nil
        }
    }

    private func drainQueue(generation processGeneration: Int, queueKey processQueueKey: String) async {
        defer {
            if processingGeneration == processGeneration {
                inFlightBatch.removeAll()
                inFlightIDs.removeAll()
            }
        }

        // Drain. A mutation enqueued while a batch is in flight would otherwise
        // sit until the next reconnect, so a user editing folders rapidly on a
        // healthy network would see a stale folder until they triggered another
        // event. Mirrors the iOS FolderSyncService loop.
        while !queue.isEmpty {
            guard !Task.isCancelled,
                  scopeGeneration == processGeneration,
                  activeQueueKey == processQueueKey else { return }
            let batch = queue
            inFlightBatch = batch
            queue.removeAll()
            inFlightIDs = Set(batch.map(\.folderID))

            let payloads = batch.map { mutation -> FolderMutationPayload in
                switch mutation {
                case .upsert(let id, let name, let color, let icon, let position):
                    return FolderMutationPayload(
                        type: "upsert",
                        id: id,
                        name: name,
                        color: color,
                        icon: icon,
                        position: position
                    )
                case .delete(let id):
                    return FolderMutationPayload(
                        type: "delete",
                        id: id,
                        name: nil,
                        color: nil,
                        icon: nil,
                        position: nil
                    )
                }
            }

            do {
                let response: FolderSyncResponse = try await apiClient.trpcMutation(
                    "folders.sync",
                    input: FolderSyncRequest(mutations: payloads)
                )
                guard !Task.isCancelled,
                      processGeneration == scopeGeneration,
                      activeQueueKey == processQueueKey else { return }

                // Mirror TaskSyncService: the server only confirms what it actually
                // accepted via `syncedIds`. Anything the server *didn't* echo back
                // is silently dropped today — log a warning and requeue so it gets
                // retried on the next attempt rather than being lost.
                let syncedSet = Set(response.syncedIds)
                let payloadIDs = payloads.map(\.id)

                let unsynced = zip(batch, payloadIDs).filter { !syncedSet.contains($0.1) }.map { $0.0 }
                if !unsynced.isEmpty {
                    AppLogger.shared.log(
                        "[FolderSyncService] server did not confirm \(unsynced.count) of \(batch.count) folder mutation(s); requeuing"
                    )
                    inFlightBatch.removeAll()
                    queue.insert(contentsOf: unsynced, at: 0)
                    // Stop draining so we don't immediately hot-loop on the same
                    // batch; the next enqueue() or retryPending() will pick it up.
                    break
                }
                inFlightBatch.removeAll()
                persistQueue()
            } catch {
                guard !Task.isCancelled,
                      processGeneration == scopeGeneration,
                      activeQueueKey == processQueueKey else { return }
                // Network / server error — requeue the batch so retryPending() can replay it.
                inFlightBatch.removeAll()
                queue.insert(contentsOf: batch, at: 0)
                AppLogger.shared.log(
                    "[FolderSyncService] sync failed; requeued \(batch.count) mutation(s): \(error.localizedDescription)"
                )
                // Stop draining on failure to avoid a hot retry loop against a down server.
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

    private func decodeJournal(forKey key: String, defaults: UserDefaults) -> [Mutation]? {
        guard let data = defaults.data(forKey: key) else { return [] }
        guard let mutations = try? JSONDecoder().decode([Mutation].self, from: data) else {
            AppLogger.shared.log("[FolderSyncService] Refusing to overwrite unreadable journal \(key)")
            return nil
        }
        return mutations
    }

    private func appendToDeferredJournal(_ mutation: Mutation, queueKey: String) {
        let defaults = UserDefaults.standard
        let key = deferredQueueKey(for: queueKey)
        guard var pending = decodeJournal(forKey: key, defaults: defaults) else { return }
        pending.append(mutation)
        if let data = try? JSONEncoder().encode(pending) {
            defaults.set(data, forKey: key)
        }
    }
}
