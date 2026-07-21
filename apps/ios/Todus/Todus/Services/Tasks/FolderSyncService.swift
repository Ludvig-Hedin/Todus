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

        var folderId: String {
            switch self {
            case .upsert(let id, _, _, _, _), .delete(let id): return id
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

    /// Persisted to UserDefaults on every change (Mutation is Codable) so offline
    /// folder edits survive an app kill — otherwise a deleted folder resurrects
    /// via `syncSharedFolders` next launch and offline creates/renames are lost
    /// forever. Mirrors `SupabaseSyncService.pendingDeleteRetries`. (TD-09)
    private var queue: [Mutation] = [] {
        didSet { persistQueue() }
    }
    /// IDs of the batch currently being sent. The queue is drained for the
    /// duration of the network call, so `hasPending(id:)` must also see
    /// in-flight mutations — that await is exactly when a concurrent
    /// `syncSharedFolders` pass can interleave.
    private var inFlightIDs: Set<String> = []
    /// The in-flight batch itself, kept for persistence: it stays in the
    /// persisted copy until its outcome is known, so an app kill mid-flight
    /// can't drop it either (upsert/delete replays are idempotent server-side).
    private var inFlightBatch: [Mutation] = []
    private var isProcessing = false
    private let apiClient: TodosAPIClient

    private static let queueKey = "TaskApp.folderMutationQueue"

    // MARK: - Init

    init(apiClient: TodosAPIClient) {
        self.apiClient = apiClient
        // Restore mutations from a previous run (offline edit → kill before reconnect).
        if let data = UserDefaults.standard.data(forKey: Self.queueKey),
           let restored = try? JSONDecoder().decode([Mutation].self, from: data) {
            queue = restored
        }
    }

    // MARK: - Public API

    /// Append a mutation to the queue and immediately attempt to flush.
    func enqueue(_ mutation: Mutation) async {
        queue.append(mutation)
        await processQueue()
    }

    /// Re-attempt any pending mutations — call this on network reconnect.
    func retryPending() async {
        await processQueue()
    }

    /// Discards any queued mutations that have not yet been sent.
    /// Call on sign-out to prevent a reconnect from replaying the previous user's edits.
    func clearQueue() {
        inFlightBatch = []
        queue.removeAll()
    }

    /// Whether a not-yet-acknowledged mutation (queued or in flight) exists for
    /// the given folder id. Lets `syncSharedFolders` skip server-wins overwrites
    /// that would revert an in-flight local rename. (TD-21a)
    func hasPending(id: String) -> Bool {
        if inFlightIDs.contains(id) { return true }
        return queue.contains { $0.folderId == id }
    }

    // MARK: - Private

    private func processQueue() async {
        guard !isProcessing, !queue.isEmpty else { return }
        isProcessing = true

        while !queue.isEmpty {
            let batch = queue
            // Keep the drained batch in the persisted copy until its outcome is
            // known — set before removeAll so the didSet persist never drops it.
            inFlightBatch = batch
            queue.removeAll()
            // Track the drained batch so hasPending(id:) stays truthful during the
            // network await below; failed sends are re-inserted into `queue`.
            inFlightIDs = Set(batch.map(\.folderId))

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
                // Server may indicate partial success; requeue any mutations whose ids
                // were not acknowledged so retryPending() can replay them.
                let synced = Set(response.syncedIds)
                let unacked = zip(batch, payloads).compactMap { mutation, payload in
                    synced.contains(payload.id) ? nil : mutation
                }
                if !unacked.isEmpty {
                    inFlightBatch = []
                    queue.insert(contentsOf: unacked, at: 0)
                    // Stop the loop on partial failure so retryPending can drive the
                    // next attempt — avoids hot-looping if the server keeps rejecting.
                    break
                }
                // Fully acked — drop the batch from the persisted copy (the queue
                // itself didn't change here, so didSet won't fire for us).
                inFlightBatch = []
                persistQueue()
            } catch {
                inFlightBatch = []
                // Network / server error — requeue the batch so retryPending() can replay it.
                queue.insert(contentsOf: batch, at: 0)
                break
            }
        }

        inFlightIDs.removeAll()
        isProcessing = false
    }

    /// Writes queued + in-flight mutations to UserDefaults; removes the key when
    /// nothing is pending. Mirrors `SupabaseSyncService.persistPendingDeleteRetries`.
    private func persistQueue() {
        let pending = inFlightBatch + queue
        if pending.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.queueKey)
        } else if let data = try? JSONEncoder().encode(pending) {
            UserDefaults.standard.set(data, forKey: Self.queueKey)
        }
    }
}
