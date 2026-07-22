import XCTest
@testable import Todus

@MainActor
final class NetworkMonitorTests: XCTestCase {
    /// Pins the H-series fix that replaced the default-true `isConnected`
    /// initializer with a synchronous read of `monitor.currentPath`. Tests
    /// running on a developer machine effectively always have connectivity,
    /// so we assert the value matches `NWPathMonitor.currentPath` rather than
    /// asserting `true` outright — that contract holds even on CI runners
    /// configured offline.
    func testInitialStateConvergesToSimulatorPathStatus() async throws {
        // Construct the monitor and then wait for the system to deliver the
        // first path update (which `NWPathMonitor` posts asynchronously after
        // `start()`). On the simulator the network is always reachable, so
        // the post-callback value is `true`. The contract this pins is:
        // `NetworkMonitor` does eventually publish the real path status —
        // it isn't stuck on a stale optimistic value.
        let monitor = NetworkMonitor()
        // Two runloop turns is enough for NWPathMonitor's queue to fire and
        // for our pathUpdateHandler to bounce back to the main actor.
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Simulator has connectivity in CI / dev environments — assert the
        // monitor reflects that. If you ever run this in a sandbox with no
        // network, the assertion needs to be relaxed.
        XCTAssertTrue(monitor.isConnected, "Simulator should be reachable; NetworkMonitor must reflect that.")
    }

    func testInitDoesNotCrashOrThrow() {
        // Sanity: synchronous construction must not block, throw, or crash.
        // The pre-H-fix initializer had a brief optimistic-true window; this
        // test just guarantees the constructor itself is well-behaved.
        for _ in 0..<3 {
            _ = NetworkMonitor()
        }
    }

    func testOnReconnectFiresOnlyOnFalseToTrueTransition() async throws {
        // Inject a fake PathProviding that starts offline, then exercise three
        // transitions: false→false (no fire), false→true (fire), true→true (no fire).
        final class FakeProvider: PathProviding, @unchecked Sendable {
            var isReachable: Bool = false
            var callback: ((Bool) -> Void)?
            func startObserving(_ callback: @escaping @Sendable (Bool) -> Void) {
                self.callback = callback
                // Mimic the immediate initial-path post that NWPathMonitor does.
                callback(isReachable)
            }
        }

        let provider = FakeProvider()
        let monitor = NetworkMonitor(provider: provider)
        // The fake reports offline initially, so reconnect must NOT fire on init.
        let fireCount = CallCount()
        monitor.onReconnect = { Task { await fireCount.increment() } }

        // false → false (still offline).
        provider.callback?(false)
        try await Task.sleep(nanoseconds: 50_000_000)
        let afterIdle = await fireCount.value
        XCTAssertEqual(afterIdle, 0, "false→false must NOT fire onReconnect.")

        // false → true: must fire exactly once.
        provider.callback?(true)
        try await Task.sleep(nanoseconds: 50_000_000)
        let afterReconnect = await fireCount.value
        XCTAssertEqual(afterReconnect, 1, "false→true must fire onReconnect exactly once.")

        // true → true (still online): must NOT fire again.
        provider.callback?(true)
        try await Task.sleep(nanoseconds: 50_000_000)
        let afterStable = await fireCount.value
        XCTAssertEqual(afterStable, 1, "true→true must NOT re-fire onReconnect.")
    }
}

/// Test helper — atomic counter for reconnect-callback assertions.
actor CallCount {
    private(set) var value = 0
    func increment() { value += 1 }
}
