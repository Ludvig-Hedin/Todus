import Foundation

/// Offline-capable queue for folder create/update/delete mutations.
/// Mutations are enqueued immediately and flushed via the tRPC `folders.sync` endpoint
/// when online. On network failure the batch is requeued and retried on reconnect.
@MainActor
final class FolderSyncService {

    // MARK: - Mutation types

    enum Mutation {
        case upsert(id: String, name: String, color: String?, icon: String?, position: Int)
        case delete(id: String)
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

    private var queue: [Mutation] = []
    private var isProcessing = false
    private let apiClient: TodosAPIClient

    // MARK: - Init

    init(apiClient: TodosAPIClient) {
        self.apiClient = apiClient
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
        queue.removeAll()
    }

    // MARK: - Private

    private func processQueue() async {
        guard !isProcessing, !queue.isEmpty else { return }
        isProcessing = true

        while !queue.isEmpty {
            let batch = queue
            queue.removeAll()

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
                    queue.insert(contentsOf: unacked, at: 0)
                    // Stop the loop on partial failure so retryPending can drive the
                    // next attempt — avoids hot-looping if the server keeps rejecting.
                    break
                }
            } catch {
                // Network / server error — requeue the batch so retryPending() can replay it.
                queue.insert(contentsOf: batch, at: 0)
                break
            }
        }

        isProcessing = false
    }
}
