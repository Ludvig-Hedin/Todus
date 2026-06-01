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

    private let log = Logger(subsystem: "com.todus.ios", category: "LocalModelStateStore")

    /// Root directory for downloaded model weights. `mlx-swift-examples` writes
    /// to `Documents/huggingface/models/<org>/<name>/` — we mirror that path so
    /// installed weights interop with any other MLX tool the user might run.
    nonisolated static var modelsDirectory: URL {
        let fm = FileManager.default
        let docs = (try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let dir = docs.appendingPathComponent("huggingface/models", isDirectory: true)
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

    /// Walks the HuggingFace cache root and seeds `.installed` for any catalog
    /// model whose `mlxRepo` matches a `<org>/<name>` subtree containing weight
    /// files. The download service writes there, so this is the source of
    /// truth for "what's actually on disk." Best-effort: weight integrity is
    /// validated later by the runtime — a corrupt download surfaces as
    /// `.failed` when loading.
    private func initialScan() async {
        defer { hasScanned = true }
        // FileManager work hops to a background priority so a user with several
        // multi-GB models on disk doesn't see the launch UI stutter while we
        // walk every weight directory.
        let seeded = await Task.detached(priority: .userInitiated) {
            Self.scanDisk()
        }.value
        // Merge instead of replace: while the scan ran, `apply(...)` may have
        // recorded in-flight `.downloading` / `.paused` / `.failed` entries
        // (e.g. user started a download right after launch). Wholesale assigning
        // `self.stateById = seeded` would silently drop them.
        //
        // Live in-flight states (`.downloading` / `.paused` / `.deleting`)
        // always win — the download service has the freshest info. But a
        // stale `.failed` from a previous attempt should yield to a real
        // on-disk `.installed`, otherwise a successful retry that completed
        // outside the store (or a download from a prior session that happens
        // to be on disk) keeps showing the old error.
        for (id, scannedState) in seeded {
            switch self.stateById[id] {
            case .none, .notInstalled, .failed:
                self.stateById[id] = scannedState
            case .downloading, .paused, .deleting, .installed:
                continue
            }
        }
        log.info("[LocalModels] Initial scan found \(seeded.count, privacy: .public) installed model(s)")
    }

    private nonisolated static func scanDisk() -> [String: LocalModelInstallState] {
        let fm = FileManager.default
        let root = Self.modelsDirectory

        var seeded: [String: LocalModelInstallState] = [:]
        for model in LocalModelCatalog.all {
            guard model.runtime == .mlx, let repo = model.mlxRepo else { continue }
            let candidate = root.appendingPathComponent(repo, isDirectory: true)
            guard fm.fileExists(atPath: candidate.path) else { continue }
            // Refuse to mark partial / failed downloads as `.installed`:
            // a `models--…/` dir with only `.lock` / `refs/` files yields
            // `directorySize > 0` but no actual weight file. The MLX runtime
            // would then crash on first turn. Gate on a real weight artifact.
            guard hasWeightFile(at: candidate, fileManager: fm) else { continue }
            // Presence is already proven by `hasWeightFile`. Don't drop the
            // entry when `directorySize` returns 0 — that can happen when
            // `totalFileAllocatedSize` is unavailable for every file
            // (sandboxed FS, network volumes), and a 0-byte report would
            // re-offer the model for download.
            let bytes = max(directorySize(at: candidate, fileManager: fm), 0)
            seeded[model.id] = .installed(diskBytes: bytes)
        }
        return seeded
    }

    /// True when the directory tree contains at least one MLX-compatible weight
    /// file (`*.safetensors`, `*.npz`, or `*.gguf`). Used by the disk scan to
    /// reject partial downloads that would crash the runtime on load.
    private nonisolated static func hasWeightFile(at url: URL, fileManager fm: FileManager) -> Bool {
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return false }
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            if ext == "safetensors" || ext == "npz" || ext == "gguf" {
                return true
            }
        }
        return false
    }

    private nonisolated static func directorySize(at url: URL, fileManager: FileManager) -> Int64 {
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
