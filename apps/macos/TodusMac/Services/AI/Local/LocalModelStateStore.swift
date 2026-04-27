import Foundation
import Observation
import OSLog

// MARK: - LocalModelInstallState
//
// Tracks per-model lifecycle state surfaced in the Local Models UI. Concrete
// download / load logic is wired in Phase 3 (MLXInferenceService +
// ModelDownloadService); this store provides the interface and persistence
// in Phase 1 so the UI can ship behind a feature flag.

enum LocalModelInstallState: Hashable {
    /// No weights on disk and no active download.
    case notInstalled
    /// Active download. `progress` is 0...1; `bytesDownloaded` / `bytesTotal`
    /// are 0 until the first response chunk arrives.
    case downloading(progress: Double, bytesDownloaded: Int64, bytesTotal: Int64)
    /// Download paused by the user. `progress` reflects how far we got.
    case paused(progress: Double, bytesDownloaded: Int64, bytesTotal: Int64)
    /// Weights present and verified. The runtime can load on demand.
    case installed(diskBytes: Int64)
    /// Currently being deleted (brief — UI keeps showing the row until removed).
    case deleting
    /// Last attempt failed. UI shows a Retry button.
    case failed(message: String)
}

extension LocalModelInstallState {
    var isInstalled: Bool {
        if case .installed = self { return true }
        return false
    }

    var isInFlight: Bool {
        switch self {
        case .downloading, .deleting:
            return true
        default:
            return false
        }
    }
}

// MARK: - LocalModelStateStore
//
// Observable source of truth for "what's downloaded, what's downloading, what
// failed." Owned at the AppServices level so multiple views (Settings → Local
// Models, the chat model picker, the chat composer's lock badge) read the
// same state without duplicating disk lookups.
//
// On initialization it scans the on-disk model directory and seeds `.installed`
// for any model whose weight files are present. Phase 3 will hook the
// `ModelDownloadService` into this store via the `apply(...)` mutation API.

@MainActor
@Observable
final class LocalModelStateStore {
    /// Per-model state keyed by `LocalModel.id`. `notInstalled` is the implied
    /// default for any model not in this map; we only persist non-default
    /// entries to keep the dictionary small.
    private(set) var stateById: [String: LocalModelInstallState] = [:]

    /// True when the initial disk scan has completed. The UI gates the
    /// "Installed" section behind this so it doesn't flash empty on launch.
    private(set) var hasScanned: Bool = false

    private let log = Logger(subsystem: "com.todus.macos", category: "LocalModelStateStore")

    /// Root directory for downloaded model weights. Same shape on iOS and
    /// macOS: Application Support / LocalModels / <model id> / ...
    static var modelsDirectory: URL {
        let fm = FileManager.default
        // Application Support is created lazily by the system; create it if
        // missing so first-run reads don't trip on the directory not existing.
        let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let dir = support.appendingPathComponent("LocalModels", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    init() {
        Task { await initialScan() }
    }

    // MARK: - Reads

    func state(for model: LocalModel) -> LocalModelInstallState {
        // Apple Foundation Models is "always installed" when the OS exposes
        // it. The UI uses ModelRecommender / DeviceProfile to gate visibility,
        // but the store treats it as installed-with-zero-disk so the chat
        // service's `isReady` check is uniform.
        if model.runtime == .appleFM { return .installed(diskBytes: 0) }
        return stateById[model.id] ?? .notInstalled
    }

    /// Convenience for view code: just the installed entries from the catalog.
    func installedModels() -> [LocalModel] {
        LocalModelCatalog.all.filter { state(for: $0).isInstalled }
    }

    /// Total disk used by all on-device weights. Surfaced in Settings header.
    func totalDiskBytes() -> Int64 {
        stateById.values.reduce(into: Int64(0)) { acc, state in
            if case .installed(let bytes) = state { acc += bytes }
        }
    }

    // MARK: - Writes (called by ModelDownloadService in Phase 3)

    /// Single mutation surface so the download/delete services don't have to
    /// know about the store's internal layout. Removing the entry by passing
    /// `.notInstalled` is fine.
    func apply(_ state: LocalModelInstallState, to modelId: String) {
        if case .notInstalled = state {
            stateById.removeValue(forKey: modelId)
        } else {
            stateById[modelId] = state
        }
    }

    // MARK: - Disk scan

    /// Walks `modelsDirectory` and seeds `.installed` for each top-level
    /// subfolder whose name matches a known catalog id and that contains at
    /// least one weight file. Best-effort — the real
    /// `ModelDownloadService` (Phase 3) writes a `manifest.json` per model
    /// for stronger validation.
    private func initialScan() async {
        defer { hasScanned = true }
        let fm = FileManager.default
        let root = Self.modelsDirectory

        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            log.info("[LocalModels] No models directory yet at \(root.path, privacy: .public)")
            return
        }

        var seeded: [String: LocalModelInstallState] = [:]
        for url in entries {
            let id = url.lastPathComponent
            guard LocalModelCatalog.model(forId: id) != nil else { continue }

            // Sum the size of every regular file inside the model dir. We
            // intentionally don't try to validate weight integrity here —
            // a corrupt download surfaces later when the runtime fails to
            // load it, and we transition to `.failed` at that point.
            let totalBytes = directorySize(at: url, fileManager: fm)
            if totalBytes > 0 {
                seeded[id] = .installed(diskBytes: totalBytes)
            }
        }
        self.stateById = seeded
        log.info("[LocalModels] Initial scan found \(seeded.count, privacy: .public) installed model(s)")
    }

    private func directorySize(at url: URL, fileManager: FileManager) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                total += Int64(values?.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
