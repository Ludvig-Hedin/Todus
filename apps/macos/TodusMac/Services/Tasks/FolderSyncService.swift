import Foundation

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
    private let apiClient: TodosAPIClient
    private var activeQueueKey: String?
    private var scopeGeneration = 0
    private var isChangingScope = false
    private static let legacyQueueKey = "TodusMac.folderMutationQueue"

    // MARK: - Init

    init(apiClient: TodosAPIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Public API

    /// Append a mutation to the queue and immediately attempt to flush.
    func enqueue(_ mutation: Mutation) async {
        guard activeQueueKey != nil else { return }
        queue.append(mutation)
        await processQueue()
    }

    /// Re-attempt any pending mutations — call this on network reconnect.
    func retryPending() async {
        guard activeQueueKey != nil else { return }
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
    func activateScope(_ scopeID: String) {
        let nextKey = "\(Self.legacyQueueKey).\(scopeID)"
        guard activeQueueKey != nextKey else { return }

        scopeGeneration += 1
        persistQueue()
        isChangingScope = true
        inFlightBatch.removeAll()
        inFlightIDs.removeAll()
        queue.removeAll()
        activeQueueKey = nextKey

        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: nextKey),
           let restored = try? JSONDecoder().decode([Mutation].self, from: data) {
            queue = restored
        }
        isChangingScope = false
        persistQueue()
    }

    func deactivateScope() {
        scopeGeneration += 1
        persistQueue()
        isChangingScope = true
        inFlightBatch.removeAll()
        inFlightIDs.removeAll()
        queue.removeAll()
        activeQueueKey = nil
        isChangingScope = false
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
        guard activeQueueKey != nil,
              processingGeneration != processGeneration,
              !queue.isEmpty else { return }
        processingGeneration = processGeneration
        defer {
            if processingGeneration == processGeneration {
                processingGeneration = nil
            }
        }

        // Drain. A mutation enqueued while a batch is in flight would otherwise
        // sit until the next reconnect, so a user editing folders rapidly on a
        // healthy network would see a stale folder until they triggered another
        // event. Mirrors the iOS FolderSyncService loop.
        while !queue.isEmpty {
            let batch = queue
            let batchGeneration = scopeGeneration
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
                guard batchGeneration == scopeGeneration, activeQueueKey != nil else { return }

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
                guard batchGeneration == scopeGeneration, activeQueueKey != nil else { return }
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

        inFlightIDs.removeAll()
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
