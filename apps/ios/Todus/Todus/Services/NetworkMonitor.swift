import Foundation
import Network
import Observation

/// Monitors network connectivity using NWPathMonitor.
/// Publishes `isConnected` for views to display offline banners.
@Observable
final class NetworkMonitor: @unchecked Sendable {
    private(set) var isConnected: Bool = true
    /// Called on the main actor whenever connectivity transitions from offline → online.
    /// Must be set from the main actor.
    @MainActor var onReconnect: (() -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private var wasConnected: Bool = true

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let previously = self.wasConnected
                self.isConnected = connected
                self.wasConnected = connected
                if connected && !previously {
                    self.onReconnect?()
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
