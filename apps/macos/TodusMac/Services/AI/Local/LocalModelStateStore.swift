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

    /// Root directory for downloaded model weights. `mlx-swift-examples` writes
    /// to `Documents/huggingface/models/<org>/<name>/`. We mirror that path so
    /// downloads interop with any other MLX tool the user runs. The
    /// `huggingface/` parent is marked `isExcludedFromBackup` the first time
    /// it's created so multi-GB weight files don't get pulled into iCloud
    /// Drive / Time Machine. Mirrors iOS.
    nonisolated static var modelsDirectory: URL {
        let fm = FileManager.default
        let docs = (try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let parent = docs.appendingPathComponent("huggingface", isDirectory: true)
        if !fm.fileExists(atPath: parent.path) {
            try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        // Apply / re-apply `isExcludedFromBackup` outside the create gate
        // so directories created by prior app versions get the flag
        // backfilled on next launch.
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

    /// External HuggingFace user cache, where the Python `huggingface_hub`
    /// CLI and `mlx_lm` write. macOS-only: the app is unsandboxed for DMG
    /// distribution, so we can probe `~/.cache/huggingface/hub/`. The standard
    /// layout is `models--<org>--<name>/snapshots/<sha>/`.
    nonisolated static var externalHuggingFaceCache: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".cache/huggingface/hub", isDirectory: true)
    }

    init() {
        Task { await initialScan() }
    }

    // MARK: - Reads

    func state(for model: LocalModel) -> LocalModelInstallState {
        // Apple Foundation Models is "installed" only when the OS actually
        // exposes it on this Mac (older hardware, regions without Apple
        // Intelligence, beta gate off → unavailable). Pre-fix this returned
        // `.installed` unconditionally and any caller that enumerated
        // installed models for a runtime pick (chat fallback, background
        // summarization, recommender) saw Apple FM as a valid choice and
        // failed at invocation time. Mirror the gate the UI already uses
        // via `DeviceProfile`.
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
        } else {
            stateById[modelId] = state
        }
    }

    // MARK: - Disk scan

    /// Walks the HuggingFace cache (and the user's external HF cache on macOS)
    /// and seeds `.installed` for any catalog model whose `mlxRepo` matches a
    /// `<org>/<name>` subtree containing weight files. Best-effort: weight
    /// integrity is validated later by the runtime — a corrupt download
    /// surfaces as `.failed` when loading.
    private func initialScan() async {
        defer { hasScanned = true }
        // Hop the FileManager walk off the main actor — iOS already does this
        // and macOS regressed to a synchronous walk on @MainActor that stutters
        // launch when the user has multi-GB caches on disk.
        let seeded = await Task.detached(priority: .userInitiated) {
            Self.scanDisk()
        }.value
        // Merge instead of replace: while the scan ran, `apply(...)` may have
        // recorded in-flight `.downloading` / `.paused` / `.failed` entries
        // (e.g. user started a download right after launch). Wholesale assigning
        // `self.stateById = seeded` would silently drop them.
        //
        // Live in-flight states win over the scan, but a stale `.failed`
        // yields to a real on-disk `.installed` so a successful retry isn't
        // pinned to the old error message.
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
        let appCache = Self.modelsDirectory
        let externalCache = Self.externalHuggingFaceCache

        var seeded: [String: LocalModelInstallState] = [:]
        for model in LocalModelCatalog.all {
            guard model.runtime == .mlx, let repo = model.mlxRepo else { continue }

            // Primary: app's Documents/huggingface/models/<repo>. Gate on a
            // real weight artifact so a `models--…/` dir with only `.lock` /
            // `refs/` (failed download) isn't reported as `.installed` and
            // then crash the runtime on first turn — match the iOS gate and
            // `HuggingFaceCacheConnector.hasWeightFile`.
            let appCandidate = appCache.appendingPathComponent(repo, isDirectory: true)
            if fm.fileExists(atPath: appCandidate.path),
               hasWeightFile(at: appCandidate, fileManager: fm) {
                // Presence proven by `hasWeightFile`. `directorySize` sums
                // unsigned allocated sizes so it can't go negative; if it
                // returns 0 (allocated size unavailable for every file)
                // fall back to `fileSize` (logical size) before resorting
                // to a 1-byte sentinel — common case shows a real number,
                // "1 B" only when both reports fail.
                var measured = directorySize(at: appCandidate, fileManager: fm)
                if measured == 0 {
                    measured = fileSizeFallback(at: appCandidate, fileManager: fm)
                }
                seeded[model.id] = .installed(diskBytes: measured > 0 ? measured : 1)
                continue
            }

            // Fallback: external HF cache, models--<org>--<name>/snapshots/<sha>/
            // Used by `huggingface_hub`, `transformers`, `mlx_lm`, and any other
            // tool the user might already have on disk.
            let externalDir = repo.replacingOccurrences(of: "/", with: "--")
            let externalCandidate = externalCache
                .appendingPathComponent("models--\(externalDir)", isDirectory: true)
            if fm.fileExists(atPath: externalCandidate.path),
               hasWeightFile(at: externalCandidate, fileManager: fm) {
                var measured = directorySize(at: externalCandidate, fileManager: fm)
                if measured == 0 {
                    measured = fileSizeFallback(at: externalCandidate, fileManager: fm)
                }
                seeded[model.id] = .installed(diskBytes: measured > 0 ? measured : 1)
            }
        }
        return seeded
    }

    private nonisolated static func directorySize(at url: URL, fileManager fm: FileManager) -> Int64 {
        // Resolve each enumerated URL to its canonical path and de-dupe.
        // Without this the external-cache walk double-counts every blob (its
        // real file under `blobs/<sha>` and its symlink alias under
        // `snapshots/<commit>/`), AND a bridged app-cache entry (which is a
        // symlink to a snapshot of symlinks-to-blobs) reports 0 bytes when
        // we simply skip symlinks. Resolving paths and de-duping handles
        // both layouts correctly. Mirror in `HuggingFaceCacheConnector`.
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

    /// Sum of logical `fileSize` over every regular file in the tree.
    /// Fallback when `directorySize`'s `totalFileAllocatedSize` is
    /// unavailable for the volume — without it the UI would render "1 B"
    /// for a real multi-GB install on sandboxed / network mounts.
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

    /// True when the directory tree contains at least one MLX-compatible
    /// weight file. Mirrors `HuggingFaceCacheConnector.hasWeightFile` so a
    /// partial / failed download isn't reported as `.installed`. Gates on
    /// `.isRegularFile` so a directory whose name happens to end in
    /// `.safetensors` / `.npz` / `.gguf` (rare in HF caches but possible
    /// for user-created or blob-fallback dirs) doesn't false-positive and
    /// crash the MLX loader on first turn.
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
}
