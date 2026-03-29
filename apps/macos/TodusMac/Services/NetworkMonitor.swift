import Foundation
import Network
import Observation

/// Monitors network connectivity using NWPathMonitor.
/// Publishes `isConnected` for views to display offline banners.
@Observable
final class NetworkMonitor: @unchecked Sendable {
    private(set) var isConnected: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
