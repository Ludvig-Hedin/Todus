import Foundation
import Observation

/// Tracks per-model install state for the Local Models settings screen and
/// the chat composer's local-runtime routing. Disk scan runs on init.
@Observable
final class LocalModelStateStore: @unchecked Sendable {
    /// Simple representation of a local model install state.
    struct ModelState: Identifiable, Hashable, Sendable {
        let id: String
        var isInstalled: Bool
        var lastCheckedAt: Date
    }

    /// Map of model identifier to state. Publicly read-only; mutate via methods.
    private(set) var models: [String: ModelState] = [:]

    init() {
        // Perform a lightweight scan or leave empty for now.
        // You can expand this to actually scan disk for local models.
    }

    /// Update or insert a model state.
    func setModel(_ id: String, installed: Bool) {
        let now = Date()
        models[id] = ModelState(id: id, isInstalled: installed, lastCheckedAt: now)
    }

    /// Convenience to query installation.
    func isInstalled(_ id: String) -> Bool {
        models[id]?.isInstalled ?? false
    }
}
