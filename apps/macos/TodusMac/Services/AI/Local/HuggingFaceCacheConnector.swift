import Foundation
import Observation
import OSLog

// MARK: - HuggingFaceCacheConnector
//
// macOS-only. Scans the user's HuggingFace caches and surfaces every MLX-
// compatible model directory found on disk — including uncurated ones the
// user pulled via `huggingface_hub`, `mlx_lm`, or another MLX tool.
//
// Two locations are probed:
//   • App cache: Documents/huggingface/models/<org>/<name>/   (mlx-swift-examples)
//   • External:  ~/.cache/huggingface/hub/models--<org>--<name>/snapshots/<sha>/
//                (huggingface_hub Python / mlx_lm / transformers)
//
// The connector itself doesn't run inference — that's `MLXInferenceService`.
// It just answers: "which on-disk models can MLX try to load?" The Local
// Models screen renders the result as a "Connected (HuggingFace)" section.

struct HuggingFaceInstalledModel: Identifiable, Hashable {
    /// Full HF repo id, e.g. "mlx-community/Qwen3-4B-4bit". Used as the
    /// chat service's `selectedModel` so MLXInferenceService loads it.
    let id: String
    /// Friendly display name (curated catalog entry's name, or the repo's
    /// last path component formatted).
    let displayName: String
    /// Approximate on-disk size (sum of all weight files we could see).
    let sizeBytes: Int64
    /// Which cache it lives in — used for the row's secondary label.
    let source: Source
    /// Absolute path to the model directory.
    let path: URL

    enum Source: String, Hashable {
        case app          // Documents/huggingface/models
        case external     // ~/.cache/huggingface/hub

        var label: String {
            switch self {
            case .app: return "In app cache"
            case .external: return "~/.cache/huggingface"
            }
        }
    }

    /// Catalog match for friendlier display name + curated metadata. Returns
    /// nil for ad-hoc pulls we don't know about.
    var curatedModel: LocalModel? {
        LocalModelCatalog.match(modelString: id)
    }
}

@MainActor
@Observable
final class HuggingFaceCacheConnector {
    /// All HuggingFace MLX-shaped model directories the connector has found.
    /// Sorted: app-cache entries first, then external; alphabetical within.
    private(set) var installedModels: [HuggingFaceInstalledModel] = []

    /// Last error from a scan attempt — surfaced in the UI when we expected
    /// to find something but couldn't (e.g. permissions issue). `nil` for
    /// the legitimate empty case (no HF models on disk yet); UI should
    /// branch on `installedModels.isEmpty` for the empty state instead of
    /// treating this string as a sentinel.
    private(set) var lastError: String?

    private let log = Logger(subsystem: "com.todus.macos", category: "HuggingFaceCacheConnector")
    private var scanTask: Task<Void, Never>?

    init() {
        refresh()
    }

    /// Trigger a fresh scan. Cancels any in-flight scan so back-to-back calls
    /// don't pile up.
    func refresh() {
        scanTask?.cancel()
        scanTask = Task { @MainActor [weak self] in
            await self?.scanNow()
        }
    }

    private func scanNow() async {
        let found = await Task.detached(priority: .userInitiated) {
            Self.collect()
        }.value
        // Honor cancellation after the detached walk completes — back-to-back
        // `refresh()` calls cancel the prior `scanTask`, but `collect()` is a
        // synchronous filesystem walk with no cancellation checks, so the old
        // task still runs to completion. Drop its result instead of letting it
        // clobber the fresher scan's `installedModels`.
        if Task.isCancelled { return }
        installedModels = found
        // Empty result is a legitimate state ("user has no HF models on
        // disk yet"), not an error. Clear `lastError` so the UI renders an
        // empty state rather than a stale error string from a previous
        // failed scan.
        lastError = nil
        log.info("[HFCache] Found \(found.count, privacy: .public) HF model(s) on disk")
    }

    // MARK: - External cache bridging
    //
    // `MLXInferenceService` is wired to `LLMModelFactory.shared` which writes
    // to `Documents/huggingface/models/<repo>/` — it has no awareness of the
    // user's `~/.cache/huggingface/hub/` cache. Without help, clicking "Use"
    // on an external entry would re-download multi-GB weights the user already
    // has on disk. Bridge by symlinking the external snapshot into the app
    // cache so the factory finds the weights locally and skips the download.
    //
    // Best-effort: failure (missing snapshot, permissions, symlink rejected)
    // falls through silently — the factory then falls back to the network and
    // the user sees a normal download.

    /// Symlink `~/.cache/huggingface/hub/models--<org>--<name>/snapshots/<sha>`
    /// into `Documents/huggingface/models/<repo>` so `LLMModelFactory` reuses
    /// the existing on-disk weights. No-op when a healthy entry already exists
    /// at the target; replaces dangling symlinks so a re-bridge after the
    /// external cache moves still works. `nonisolated` because the body only
    /// touches `FileManager` (thread-safe for this usage) and no main-actor
    /// state — keeping it `@MainActor` would block the main thread on disk I/O
    /// the first time the user picks an external model.
    nonisolated static func bridgeIntoAppCacheIfPossible(
        _ entry: HuggingFaceInstalledModel,
        log: Logger? = nil
    ) {
        guard entry.source == .external else { return }
        let fm = FileManager.default
        let appCache = LocalModelStateStore.modelsDirectory
        let target = appCache.appendingPathComponent(entry.id, isDirectory: true)

        // Resolve the desired source snapshot FIRST so we can compare against
        // an existing live symlink — without this comparison, a previously
        // bridged repo keeps pointing at the old snapshot even after the
        // user pulls a new commit (HF moves `refs/main` and we'd never see
        // the update). Validate the `refs/main` payload looks like a real
        // hex commit hash before using it as a path component — defends
        // against a malformed or tampered refs file embedding `../` etc.
        // and pointing the symlink outside the snapshots dir.
        let refsMain = entry.path.appendingPathComponent("refs/main")
        var sha: String?
        if let data = try? Data(contentsOf: refsMain),
           let s = String(data: data, encoding: .utf8)?
               .trimmingCharacters(in: .whitespacesAndNewlines),
           !s.isEmpty,
           s.count <= 64,
           Self.isAsciiHex(s) {
            sha = s
        }
        let snapshotsDir = entry.path.appendingPathComponent("snapshots", isDirectory: true)

        // Candidate list newest-first: `refs/main` (canonical) then mtime
        // fallback. Iterate all and pick the first dir that has real
        // weights — picking only the newest gave up entirely when HF left
        // an aborted snapshot newer than a healthy one.
        var candidates: [URL] = []
        if let sha {
            candidates.append(snapshotsDir.appendingPathComponent(sha, isDirectory: true))
        }
        let snapshotEntries = (try? fm.contentsOfDirectory(
            at: snapshotsDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let dirs = snapshotEntries.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
        let sortedByMtime = dirs.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return da > db
        }
        candidates.append(contentsOf: sortedByMtime)

        var seen = Set<String>()
        let source = candidates.first { url in
            guard seen.insert(url.path).inserted else { return false }
            return fm.fileExists(atPath: url.path)
                && hasWeightFile(at: url, fileManager: fm)
        }
        guard let source else {
            log?.warning("[HFBridge] Skipped \(entry.id, privacy: .public): no snapshot with weights under \(snapshotsDir.path, privacy: .public)")
            return
        }
        // Resolve symlinks in path components too — `~/Documents`, `~/.cache`,
        // or their ancestors may themselves be symlinks (external volume,
        // user alias). Without `.resolvingSymlinksInPath()` the equality
        // check against a destination URL — which Foundation does fully
        // resolve — spuriously fails, and the bridge tears down and
        // recreates the symlink on every refresh.
        let canonicalSource = source.resolvingSymlinksInPath().standardizedFileURL.path
        // Containment check: refuse to symlink into anywhere outside the
        // expected external HF cache root. `contentsOfDirectory` doesn't
        // recurse but each entry under `snapshots/` COULD be a symlink
        // pointing outside the cache. Validate before treating any path
        // as a trusted source.
        let externalRoot = LocalModelStateStore.externalHuggingFaceCache
            .resolvingSymlinksInPath().standardizedFileURL.path
        if !canonicalSource.hasPrefix(externalRoot + "/") {
            log?.error("[HFBridge] Refused \(entry.id, privacy: .public): resolved source \(canonicalSource, privacy: .public) escapes \(externalRoot, privacy: .public)")
            return
        }

        // Inspect the target. `fileExists` follows symlinks, so a *dangling*
        // symlink reports false — we ask only for `.isSymbolicLinkKey`
        // (lstat semantics) to distinguish the cases:
        //   - live symlink pointing at `source`  → already up to date, done
        //   - live symlink pointing elsewhere    → stale, repoint to `source`
        //   - dangling symlink                   → remove + recreate
        //   - real regular dir                   → leave alone (real download)
        let symLinkValues = try? target.resourceValues(forKeys: [.isSymbolicLinkKey])
        if symLinkValues?.isSymbolicLink == true {
            if let destPath = try? fm.destinationOfSymbolicLink(atPath: target.path) {
                let resolvedDest = URL(fileURLWithPath: destPath, relativeTo: target.deletingLastPathComponent())
                    .resolvingSymlinksInPath()
                    .standardizedFileURL.path
                if resolvedDest == canonicalSource, fm.fileExists(atPath: target.path) {
                    // Live symlink to the same snapshot — nothing to do.
                    return
                }
            }
            // Stale or dangling — remove so we can re-create. Surface
            // removal failures (typically permissions) into the log so a
            // "MLX keeps re-downloading multi-GB weights" support ticket
            // can be diagnosed at the right layer instead of looking like
            // an inference bug.
            // TODO(bug-hunt): Non-atomic symlink replace. bridgeIntoAppCacheIfPossible
            // is nonisolated static with no serialization, so two concurrent refresh()
            // calls (or a concurrent real download) can interleave between this
            // removeItem and the createSymbolicLink below, leaving a missing/stale link
            // → MLX re-downloads multi-GB weights (the exact symptom this bridge prevents).
            // Fix: create the link at a temp path in the same dir, then
            // fm.replaceItemAt(target, withItemAt: tempLink) for an atomic rename.
            do {
                try fm.removeItem(at: target)
            } catch {
                log?.error("[HFBridge] Failed to remove stale symlink at \(target.path, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        } else if fm.fileExists(atPath: target.path) {
            // Real regular directory at the target (live download or other
            // pre-existing content). Never touch — the factory will decide.
            return
        }

        let parent = target.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: target, withDestinationURL: source)
            log?.info("[HFBridge] Linked \(entry.id, privacy: .public) → \(source.path, privacy: .public)")
        } catch {
            // Permissions, sandbox surprise, or a race — let MLX fall through
            // to its normal HF download path. Log so we can diagnose silent
            // re-downloads in support tickets.
            log?.error("[HFBridge] Failed to link \(entry.id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Scan

    private nonisolated static func collect() -> [HuggingFaceInstalledModel] {
        var results: [HuggingFaceInstalledModel] = []
        results.append(contentsOf: collectAppCache())
        results.append(contentsOf: collectExternalCache())
        // De-dupe by repo id, preferring the `.app` entry. Without this a
        // bridged model (external → app via `bridgeIntoAppCacheIfPossible`)
        // appears in BOTH `collectAppCache()` (the symlinked dir) and
        // `collectExternalCache()` (its original source), and SwiftUI's
        // `ForEach(..., id: \.element.id)` then has duplicate ids and either
        // logs an error or drops rows unpredictably.
        var seen = Set<String>()
        let deduped = results.filter { entry in
            seen.insert(entry.id).inserted
        }
        return deduped.sorted { a, b in
            if a.source != b.source {
                return a.source == .app
            }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    /// `Documents/huggingface/models/<org>/<name>/`. mlx-swift-examples writes
    /// here on first download.
    private nonisolated static func collectAppCache() -> [HuggingFaceInstalledModel] {
        let fm = FileManager.default
        let root = LocalModelStateStore.modelsDirectory
        guard fm.fileExists(atPath: root.path) else { return [] }

        var out: [HuggingFaceInstalledModel] = []
        guard let orgs = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return [] }

        for orgURL in orgs {
            guard isDir(orgURL, fileManager: fm) else { continue }
            guard let names = try? fm.contentsOfDirectory(
                at: orgURL, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ) else { continue }
            for nameURL in names {
                guard isDir(nameURL, fileManager: fm) else { continue }
                guard hasWeightFile(at: nameURL, fileManager: fm) else { continue }
                let repo = "\(orgURL.lastPathComponent)/\(nameURL.lastPathComponent)"
                let bytes = directorySize(at: nameURL, fileManager: fm)
                let display = LocalModelCatalog.match(modelString: repo)?.displayName
                    ?? humanize(repo: repo)
                out.append(HuggingFaceInstalledModel(
                    id: repo, displayName: display, sizeBytes: bytes,
                    source: .app, path: nameURL
                ))
            }
        }
        return out
    }

    /// `~/.cache/huggingface/hub/models--<org>--<name>/snapshots/<sha>/`. Used
    /// by every Python-side HF tool. macOS only — iOS apps can't read this.
    private nonisolated static func collectExternalCache() -> [HuggingFaceInstalledModel] {
        let fm = FileManager.default
        let root = LocalModelStateStore.externalHuggingFaceCache
        guard fm.fileExists(atPath: root.path) else { return [] }

        var out: [HuggingFaceInstalledModel] = []
        guard let entries = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return [] }

        for url in entries {
            let name = url.lastPathComponent
            guard name.hasPrefix("models--") else { continue }
            // Decode "models--mlx-community--Qwen3-4B-4bit" → "mlx-community/Qwen3-4B-4bit"
            let stripped = String(name.dropFirst("models--".count))
            let parts = stripped.components(separatedBy: "--")
            guard parts.count >= 2 else { continue }
            let org = parts[0]
            let modelName = parts.dropFirst().joined(separator: "--")
            let repo = "\(org)/\(modelName)"

            // Only surface mlx-community/ repos — the canonical HuggingFace org
            // for quantized MLX models. Vanilla PyTorch weights from other orgs
            // can't run via MLX. Expand this guard if we ever support other
            // MLX-compatible orgs (e.g. apple-mlx/).
            guard repo.hasPrefix("mlx-community/") else { continue }

            let snapshots = url.appendingPathComponent("snapshots", isDirectory: true)
            guard hasWeightFile(at: snapshots, fileManager: fm) else { continue }
            let bytes = directorySize(at: url, fileManager: fm)
            let display = LocalModelCatalog.match(modelString: repo)?.displayName
                ?? humanize(repo: repo)
            out.append(HuggingFaceInstalledModel(
                id: repo, displayName: display, sizeBytes: bytes,
                source: .external, path: url
            ))
        }
        return out
    }

    // MARK: - Helpers

    private nonisolated static func isDir(_ url: URL, fileManager fm: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        return isDirectory.boolValue
    }

    /// Detects whether the directory tree contains at least one weight file
    /// (`*.safetensors`, `*.npz`, or `*.gguf`). Saves us from listing partial /
    /// failed downloads as installed. Gates on `.isRegularFile` so a directory
    /// whose name happens to end in one of those extensions doesn't false-
    /// positive and crash the MLX loader.
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
        // HF's cache layout has two cases that naive enumeration mishandles:
        //   1. External `models--<org>--<name>/` contains BOTH real files
        //      under `blobs/<sha>` and symlink aliases under
        //      `snapshots/<commit>/*.safetensors` pointing at the same blob.
        //   2. Bridged app-cache entries are themselves a symlink to a
        //      snapshot, so every file under them is a symlink to a blob.
        //
        // Skipping symlinks fixes case 1 but breaks case 2 (every weight is
        // a symlink → reported size is 0). Following symlinks fixes case 2
        // but breaks case 1 (each blob counted twice).
        //
        // Resolve every URL to its canonical filesystem path before counting
        // and de-dupe — a blob enumerated via two paths (real + symlink)
        // contributes once; a snapshot-of-symlinks resolves each file back
        // to its blob and sums them correctly.
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

    /// Strict ASCII-hex check. Swift's `Character.isHexDigit` accepts
    /// Unicode-equivalents (Arabic-Indic digits, fullwidth Latin letters)
    /// which a git SHA never contains. The downstream containment check
    /// catches escapes anyway, but this is defense-in-depth.
    private nonisolated static func isAsciiHex(_ s: String) -> Bool {
        for scalar in s.unicodeScalars {
            let v = scalar.value
            let isDigit = v >= 0x30 && v <= 0x39       // '0'...'9'
            let isUpper = v >= 0x41 && v <= 0x46       // 'A'...'F'
            let isLower = v >= 0x61 && v <= 0x66       // 'a'...'f'
            if !(isDigit || isUpper || isLower) { return false }
        }
        return true
    }

    private nonisolated static func humanize(repo: String) -> String {
        // "mlx-community/Qwen3-4B-4bit" → "Qwen3 4B 4bit"
        let name = repo.split(separator: "/").last.map(String.init) ?? repo
        return name.replacingOccurrences(of: "-", with: " ")
    }
}
