import Foundation

/// Tracks per-model install state for the Local Models settings screen and
/// the chat composer's local-runtime routing. This is a lightweight placeholder
/// so the project compiles; extend with real disk scanning and model metadata as needed.
@MainActor
final class LocalModelStateStore {
    /// Simple representation of a local model installation.
    struct InstalledModel: Identifiable, Hashable, Codable {
        let id: String          // e.g. model identifier
        var displayName: String // human-friendly name
        var isDownloaded: Bool
        var sizeBytes: Int64
    }

    /// All models known to the app (downloaded or available).
    private(set) var models: [InstalledModel] = []

    /// Last time a disk scan completed.
    private(set) var lastScanDate: Date?

    init() {
        // Perform a lightweight synchronous scan placeholder.
        // Replace with real filesystem checks if/when needed.
        self.models = []
        self.lastScanDate = nil
        Task { [weak self] in await self?.scanDiskForModels() }
    }

    /// Simulate a disk scan to populate `models`.
    func scanDiskForModels() async {
        // In a real implementation, enumerate your app's model storage location,
        // compute sizes, and set the appropriate flags.
        // For now, provide an empty list and mark the time so UI can react.
        self.lastScanDate = Date()
    }

    /// Replace or upsert a model entry.
    func upsert(model: InstalledModel) {
        if let idx = models.firstIndex(where: { $0.id == model.id }) {
            models[idx] = model
        } else {
            models.append(model)
        }
    }

    /// Remove a model by identifier.
    func removeModel(id: String) {
        models.removeAll { $0.id == id }
    }
}
