import Foundation
import Observation

// NOTE: This file name conflicts with Services/ConnectionsService.swift.
// Rename this file in Xcode to "AppConnectionsServicePlaceholder.swift" or remove it from the target.
// Until then, this file is excluded from compilation with `#if false` to avoid build errors.

#if false
@available(*, unavailable, message: "Use Services/ConnectionsService instead.")
@MainActor
@Observable
final class AppConnectionsServicePlaceholder {
    private weak var apiClient: TodosAPIClient?

    // Example state that a connections feature might track
    var isLoading: Bool = false
    var errorMessage: String? = nil

    @available(*, unavailable)
    init(api: TodosAPIClient) {
        self.apiClient = api
    }

    // Placeholder: load a list of connections from backend
    func loadConnections() async {
        isLoading = true
        defer { isLoading = false }
        // Implement TRPC calls when backend routes are available, e.g.:
        // struct Response: Decodable { let connections: [Connection] }
        // do { let _: Response = try await apiClient?.trpcQuery("connections.list") } catch { errorMessage = error.localizedDescription }
    }

    // Placeholder: add a new connection
    func addConnection(userId: String) async -> Bool {
        // Implement when backend route exists
        // struct Input: Encodable { let userId: String }
        // do { let _: EmptyResponse = try await apiClient?.trpcMutation("connections.add", input: Input(userId: userId)) } catch { errorMessage = error.localizedDescription; return false }
        return false
    }
}
#endif
