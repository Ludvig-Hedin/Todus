import Foundation
import Network
import Observation

/// Connectivity observer seam — `NWPathMonitor` is wrapped behind this protocol
/// so unit tests can drive synthetic false→true transitions without depending
/// on the simulator's actual network. Default impl forwards to `NWPathMonitor`.
protocol PathProviding: AnyObject {
    var isReachable: Bool { get }
    /// Starts observing path updates. The callback is invoked once with the
    /// current path immediately on start, then on every subsequent change.
    func startObserving(_ callback: @escaping @Sendable (Bool) -> Void)
}

/// Default `PathProviding` impl backed by `NWPathMonitor`.
final class NWPathProvider: PathProviding, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    var isReachable: Bool { monitor.currentPath.status == .satisfied }

    func startObserving(_ callback: @escaping @Sendable (Bool) -> Void) {
        monitor.pathUpdateHandler = { path in
            callback(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

/// Monitors network connectivity using NWPathMonitor.
/// Publishes `isConnected` for views to display offline banners.
@Observable
final class NetworkMonitor: @unchecked Sendable {
    /// Seeded synchronously from `monitor.currentPath` in `init`. Default-true was a
    /// false advertisement for the brief window before the first path callback,
    /// causing the offline banner to flicker on cold launch on a flaky connection.
    private(set) var isConnected: Bool
    /// Called on the main actor whenever connectivity transitions from offline → online.
    /// Must be set from the main actor.
    @MainActor var onReconnect: (() -> Void)?

    private let provider: PathProviding
    private var wasConnected: Bool

    convenience init() {
        self.init(provider: NWPathProvider())
    }

    /// Internal designated init that accepts a `PathProviding`. Used by tests
    /// to inject a fake provider whose synthetic path transitions exercise
    /// the false→true reconnect branch.
    init(provider: PathProviding) {
        self.provider = provider
        // Read the synchronous snapshot once before starting the monitor so
        // `isConnected` reflects reality from the first frame instead of
        // optimistically claiming a connection that may not exist.
        let initial = provider.isReachable
        self.isConnected = initial
        self.wasConnected = initial

        provider.startObserving { [weak self] connected in
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
    }
}
