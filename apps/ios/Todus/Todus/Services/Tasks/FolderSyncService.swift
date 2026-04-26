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

    // MARK: - Private

    private func processQueue() async {
        guard !isProcessing, !queue.isEmpty else { return }
        isProcessing = true
        defer { isProcessing = false }

        let batch = queue
        queue.removeAll()

        do {
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

            let _: FolderSyncResponse = try await apiClient.trpcMutation(
                "folders.sync",
                input: FolderSyncRequest(mutations: payloads)
            )
        } catch {
            // Network / server error — requeue the batch so retryPending() can replay it.
            queue.insert(contentsOf: batch, at: 0)
        }
    }
}
