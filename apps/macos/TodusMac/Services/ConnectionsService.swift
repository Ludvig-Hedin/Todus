import Foundation
import Observation

/// Represents a connected email account (Google, Microsoft, etc.)
/// Used for multi-account support — each connection maps to one OAuth-linked mailbox.
struct ConnectionAccount: Identifiable, Codable, Sendable {
    let id: String
    let email: String
    let name: String?
    let picture: String?
    let providerId: String
    let color: String?

    var displayColor: String {
        color ?? "#007AFF"
    }
}

// MARK: - TRPC Response Types

private struct ConnectionsListResponse: Codable {
    let connections: [ConnectionAccount]
    let disconnectedIds: [String]
}

private struct ConnectionsListTRPCResponse: Codable {
    let result: ConnectionsListResultData
    struct ConnectionsListResultData: Codable {
        let data: ConnectionsListResponse
    }
}

// MARK: - ConnectionsService

/// Manages multi-account email connections.
/// Fetches the list of connected accounts from the backend and tracks
/// which connections are currently enabled for filtering email views.
@MainActor
@Observable
final class ConnectionsService {
    private let api: TodosAPIClient
    private let defaults = UserDefaults.standard
    private var hasInitializedConnections = false

    private enum Keys {
        static let enabledConnectionIds = "Todus.enabledConnectionIds"
    }

    var connections: [ConnectionAccount] = []
    var disconnectedIds: Set<String> = []
    var enabledConnectionIds: Set<String> {
        didSet {
            defaults.set(Array(enabledConnectionIds), forKey: Keys.enabledConnectionIds)
        }
    }
    var isLoading = false
    var loadError: String?

    var hasMultipleConnections: Bool { connections.count > 1 }
    var isAllEnabled: Bool {
        connections.allSatisfy { enabledConnectionIds.contains($0.id) }
    }

    init(api: TodosAPIClient) {
        self.api = api
        let stored = defaults.stringArray(forKey: Keys.enabledConnectionIds)
        self.enabledConnectionIds = Set(stored ?? [])
        self.hasInitializedConnections = stored != nil
    }

    /// Fetches the list of connections from the backend.
    /// On first load (no stored preferences), enables all connections by default.
    func loadConnections() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let response: ConnectionsListResponse = try await api.trpcQuery("connections.list")
            connections = response.connections
            disconnectedIds = Set(response.disconnectedIds)

            // First load: enable all connections by default
            if !hasInitializedConnections && enabledConnectionIds.isEmpty {
                enabledConnectionIds = Set(connections.map(\.id))
                hasInitializedConnections = true
            } else {
                // Prune stale IDs that no longer exist on the backend
                let currentIds = Set(connections.map(\.id))
                enabledConnectionIds = enabledConnectionIds.intersection(currentIds)
                if enabledConnectionIds.isEmpty {
                    enabledConnectionIds = Set(connections.map(\.id))
                }
                hasInitializedConnections = true
            }
        } catch {
            loadError = error.localizedDescription
            AppLogger.shared.log("[ConnectionsService] Failed to load connections: \(error)")
        }
    }

    /// Toggles a connection's enabled state. Prevents disabling the last enabled connection.
    func toggleConnection(_ id: String) {
        if enabledConnectionIds.contains(id) {
            // Don't allow disabling the last connection
            guard enabledConnectionIds.count > 1 else { return }
            enabledConnectionIds.remove(id)
        } else {
            enabledConnectionIds.insert(id)
        }
    }

    /// Enables all connections.
    func enableAll() {
        enabledConnectionIds = Set(connections.map(\.id))
    }

    /// Sets the default connection on the backend.
    func setDefault(connectionId: String) async throws {
        struct Input: Encodable { let connectionId: String }
        struct SetDefaultResponse: Codable { let success: Bool? }
        let response: SetDefaultResponse = try await api.trpcMutation(
            "connections.setDefault",
            input: Input(connectionId: connectionId)
        )
        guard response.success == true else {
            throw URLError(.badServerResponse)
        }
    }

    /// Checks whether a connection is in a disconnected state (needs re-auth).
    func isDisconnected(_ connectionId: String) -> Bool {
        disconnectedIds.contains(connectionId)
    }
}
