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

    /// Deletions that occur while the detached launch scan is walking disk.
    /// Without this tombstone, the scan's stale snapshot can reinsert a model
    /// as installed immediately after the user deletes it.
    private var deletedDuringInitialScan: Set<String> = []

    private let log = Logger(subsystem: "com.todus.ios", category: "LocalModelStateStore")

    /// Root directory for downloaded model weights. `mlx-swift-examples` writes
    /// to `Documents/huggingface/models/<org>/<name>/` — we mirror that path so
    /// installed weights interop with any other MLX tool the user might run.
    /// The `huggingface/` parent is marked `isExcludedFromBackup` the first
    /// time it's created so multi-GB weight files don't balloon the user's
    /// iCloud backup quota and slow restores.
    nonisolated static var modelsDirectory: URL {
        let fm = FileManager.default
        let docs = (try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let parent = docs.appendingPathComponent("huggingface", isDirectory: true)
        if !fm.fileExists(atPath: parent.path) {
            try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        // Apply / re-apply `isExcludedFromBackup` outside the create gate
        // so a directory created by a prior app version still gets the
        // flag backfilled on next launch (otherwise existing users would
        // never see the iCloud-backup exclusion).
        var mutableParent = parent
        let alreadyExcluded = (try? mutableParent.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) ?? false
        if !alreadyExcluded {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? mutableParent.setResourceValues(values)
        }
        let dir = parent.appendingPathComponent("models", isDirectory: true)
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
        // Apple Foundation Models is "installed" only when the OS actually
        // exposes it on this iPhone (older devices, regions without Apple
        // Intelligence, beta gate off → unavailable). Pre-fix this returned
        // `.installed` unconditionally and any caller enumerating installed
        // models for a runtime pick would see Apple FM and fail at
        // invocation time. Mirror macOS + the UI's `DeviceProfile` gate.
        if model.runtime == .appleFM {
            return DeviceProfile.current.appleFMAvailable
                ? .installed(diskBytes: 0)
                : .notInstalled
        }
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
            if !hasScanned { deletedDuringInitialScan.insert(modelId) }
        } else {
            deletedDuringInitialScan.remove(modelId)
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
            guard !deletedDuringInitialScan.contains(id) else { continue }
            switch self.stateById[id] {
            case .none, .notInstalled, .failed:
                self.stateById[id] = scannedState
            case .downloading, .paused, .deleting, .installed:
                continue
            }
        }
        deletedDuringInitialScan.removeAll()
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
            // Presence is already proven by `hasWeightFile`. `directorySize`
            // sums unsigned allocated sizes so it can't go negative — but
            // it CAN return 0 when `totalFileAllocatedSize` is unavailable
            // for every file (sandboxed FS, network volumes). Fall back to
            // `fileSize` (the un-rounded logical size) before resorting to
            // a 1-byte sentinel, so the UI shows a real number for the
            // common case and "1 B" only when both reports fail.
            var measured = directorySize(at: candidate, fileManager: fm)
            if measured == 0 {
                measured = fileSizeFallback(at: candidate, fileManager: fm)
            }
            seeded[model.id] = .installed(diskBytes: measured > 0 ? measured : 1)
        }
        return seeded
    }

    /// Sum of `fileSize` (logical) over every regular file in the tree.
    /// Used as a fallback when `directorySize` returns 0 because
    /// `totalFileAllocatedSize` is unavailable for the volume (sandboxed
    /// mounts, network drives) — without this the UI would render "1 B"
    /// for a real multi-GB install.
    private nonisolated static func fileSizeFallback(at url: URL, fileManager fm: FileManager) -> Int64 {
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        var seen = Set<String>()
        for case let fileURL as URL in enumerator {
            let resolvedPath = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
            if !seen.insert(resolvedPath).inserted { continue }
            let resolvedURL = URL(fileURLWithPath: resolvedPath)
            let values = try? resolvedURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true, let size = values?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// True when the directory tree contains at least one MLX-compatible weight
    /// file (`*.safetensors`, `*.npz`, or `*.gguf`). Used by the disk scan to
    /// reject partial downloads that would crash the runtime on load. Gates on
    /// `.isRegularFile` so a directory whose name happens to end in one of
    /// those extensions doesn't false-positive.
    private nonisolated static func hasWeightFile(at url: URL, fileManager fm: FileManager) -> Bool {
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return false }
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let ext = fileURL.pathExtension.lowercased()
            if ext == "safetensors" || ext == "npz" || ext == "gguf" {
                return true
            }
        }
        return false
    }

    private nonisolated static func directorySize(at url: URL, fileManager fm: FileManager) -> Int64 {
        // Resolve and de-dupe by canonical path so the HF blob+snapshot
        // layout (real file under `blobs/<sha>` plus a symlink alias under
        // `snapshots/<commit>/...`) doesn't double-count, and a tree of
        // symlinks-pointing-at-real-files doesn't undercount. iOS today only
        // probes `Documents/huggingface/models/<repo>` written by
        // `mlx-swift-examples`, but if that path ever ships a symlinked
        // snapshot the math stays consistent across platforms (mirrors
        // macOS `directorySize`).
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        var seen = Set<String>()
        for case let fileURL as URL in enumerator {
            let resolvedPath = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
            if !seen.insert(resolvedPath).inserted { continue }
            let resolvedURL = URL(fileURLWithPath: resolvedPath)
            let values = try? resolvedURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                total += Int64(values?.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
