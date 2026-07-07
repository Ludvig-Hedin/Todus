import Foundation
import Observation

/// Represents a connected email account (Google, Microsoft, etc.)
struct ConnectionAccount: Identifiable, Codable, Sendable {
    let id: String
    let email: String
    let name: String?
    let picture: String?
    let providerId: String
    let color: String?

    /// Auto-assigned color from palette when server color is nil
    var displayColor: String {
        color ?? "#007AFF"
    }

    /// Human-readable provider name derived from providerId
    var providerName: String {
        switch providerId {
        case "google": return "Google"
        case "microsoft": return "Microsoft"
        case "apple": return "Apple"
        default: return providerId.capitalized
        }
    }
}

/// Response shape for the connections.list tRPC query (after superjson unwrap by TodosAPIClient)
private struct ConnectionsListResponse: Codable {
    let connections: [ConnectionAccount]
    let disconnectedIds: [String]
}

/// Multi-account connections service — fetches connected email accounts from the backend
/// and manages which accounts are visible (enabled) for filtering in the UI.
@MainActor
@Observable
final class ConnectionsService {
    private let api: TodosAPIClient
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let enabledConnectionIds = "Todus.enabledConnectionIds"
    }

    /// All connected accounts fetched from the backend
    var connections: [ConnectionAccount] = []
    /// IDs of disconnected accounts (expired tokens, missing credentials)
    var disconnectedIds: Set<String> = []
    /// Connection IDs currently visible in the app — used for email filtering.
    /// Persisted to UserDefaults so the filter state survives app restarts.
    var enabledConnectionIds: Set<String> {
        didSet {
            defaults.set(Array(enabledConnectionIds), forKey: Keys.enabledConnectionIds)
        }
    }
    /// Whether we're currently loading connections from the backend
    var isLoading = false
    /// Error message from the last load attempt, if any
    var loadError: String?

    /// Whether the user has more than one connected account
    var hasMultipleConnections: Bool { connections.count > 1 }

    /// Whether all connections are currently enabled (visible)
    var isAllEnabled: Bool {
        connections.allSatisfy { enabledConnectionIds.contains($0.id) }
    }

    init(api: TodosAPIClient) {
        self.api = api
        // Restore persisted filter state from UserDefaults
        let stored = defaults.stringArray(forKey: Keys.enabledConnectionIds)
        self.enabledConnectionIds = Set(stored ?? [])
    }

    /// Load all connections from the backend via connections.list tRPC query
    func loadConnections() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let response: ConnectionsListResponse = try await api.trpcQuery("connections.list")
            connections = response.connections
            disconnectedIds = Set(response.disconnectedIds)

            let currentIds = Set(connections.map(\.id))
            let hadStoredState = defaults.stringArray(forKey: Keys.enabledConnectionIds) != nil

            if !hadStoredState || enabledConnectionIds.isEmpty {
                // No persisted filter state — enable all connections by default
                enabledConnectionIds = currentIds
            } else {
                // Clean up stale IDs (removed connections) and add new ones as enabled
                var updated = enabledConnectionIds.intersection(currentIds)
                let newIds = currentIds.subtracting(updated)
                updated.formUnion(newIds)
                enabledConnectionIds = updated
            }
        } catch {
            loadError = error.localizedDescription
            AppLogger.shared.log("[ConnectionsService] Failed to load connections: \(error)")
        }
    }

    /// Toggle a connection's visibility in the email filter.
    /// Prevents disabling the last remaining connection.
    func toggleConnection(_ id: String) {
        if enabledConnectionIds.contains(id) {
            // Don't allow hiding the last connection — at least one must stay visible
            guard enabledConnectionIds.count > 1 else { return }
            enabledConnectionIds.remove(id)
        } else {
            enabledConnectionIds.insert(id)
        }
    }

    /// Enable all connections (show everything)
    func enableAll() {
        enabledConnectionIds = Set(connections.map(\.id))
    }

    /// Set a connection as the default "from" address for composing emails
    func setDefault(connectionId: String) async throws {
        struct Input: Encodable { let connectionId: String }
        let _: EmptyResponse = try await api.trpcMutation(
            "connections.setDefault",
            input: Input(connectionId: connectionId)
        )
    }

    /// Delete a connection from the backend and refresh the local list
    func deleteConnection(connectionId: String) async throws {
        struct Input: Encodable { let connectionId: String }
        let _: EmptyResponse = try await api.trpcMutation(
            "connections.delete",
            input: Input(connectionId: connectionId)
        )
        // Refresh the list after deletion so UI stays in sync
        await loadConnections()
    }

    /// Check if a connection has expired/invalid tokens
    func isDisconnected(_ connectionId: String) -> Bool {
        disconnectedIds.contains(connectionId)
    }
}
