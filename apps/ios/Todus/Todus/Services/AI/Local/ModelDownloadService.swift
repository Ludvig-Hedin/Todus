import Foundation
import OSLog

#if canImport(MLXLLM) && canImport(MLXLMCommon)
import MLXLLM
import MLXLMCommon
#endif

// MARK: - ModelDownloadService
//
// User-facing download orchestration for MLX models. The actual transfer is
// performed by `mlx-swift-examples`'s `LLMModelFactory`, which already mirrors
// the HuggingFace cache layout — we just bridge its progress callbacks into
// our `LocalModelStateStore` so the Settings UI shows a live progress bar
// and the chat service can read "is this ready" without knowing about MLX.
//
// What this gives the user:
//   • Tap Download in Settings → Local Models → progress bar starts
//   • Cancel mid-download → state goes back to .notInstalled (cancellation
//     leaves a partial cache, but `loadContainer` will resume next time)
//   • Delete weights → blow away the per-model directory
//
// What this does NOT do (yet):
//   • True pause/resume across app launches. MLX's downloader doesn't expose
//     a "pause" knob, so cancelling currently sets state to `.notInstalled`.
//   • Background URLSession transfers. The HuggingFace transfer happens in
//     the foreground task; backgrounding the app may suspend it. Phase 7
//     follow-up.

@MainActor
@Observable
final class ModelDownloadService {
    private weak var stateStore: LocalModelStateStore?
    private weak var inferenceService: MLXInferenceService?
    /// Active download tasks keyed by model id. Tasks catch their own errors
    /// (failures route through `LocalModelStateStore.apply(.failed)`), so the
    /// task type is `Task<Void, Never>` rather than `Task<Void, Error>`.
    private var inFlight: [String: Task<Void, Never>] = [:]
    private let log = Logger(subsystem: "com.todus.ios", category: "ModelDownloadService")

    init(stateStore: LocalModelStateStore, inferenceService: MLXInferenceService) {
        self.stateStore = stateStore
        self.inferenceService = inferenceService
    }

    // MARK: - Public API

    /// Start a download for `model`. Idempotent — calling twice returns the
    /// existing task. State store transitions: notInstalled → downloading(...)
    /// → installed | failed. The chat service is free to call
    /// `MLXInferenceService.warmUp` after the task completes for zero-latency
    /// first-token on the next chat.
    func startDownload(_ model: LocalModel) {
        guard model.runtime == .mlx else { return }
        guard let store = stateStore else { return }
        if let task = inFlight[model.id], !task.isCancelled { return }

        let totalBytes = Int64(model.downloadSizeMB) * 1_000_000
        store.apply(
            .downloading(progress: 0, bytesDownloaded: 0, bytesTotal: totalBytes),
            to: model.id
        )

        let task = Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.inFlight[model.id] = nil } }
            do {
                try await self.runDownload(model)
            } catch is CancellationError {
                store.apply(.notInstalled, to: model.id)
            } catch {
                self.log.error("[Download] \(model.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                store.apply(.failed(message: error.localizedDescription), to: model.id)
            }
        }
        inFlight[model.id] = task
    }

    /// Cancel an in-flight download. State store transitions back to
    /// `.notInstalled` so the row's Download button reappears.
    func cancelDownload(_ modelId: String) {
        inFlight[modelId]?.cancel()
        inFlight.removeValue(forKey: modelId)
        stateStore?.apply(.notInstalled, to: modelId)
    }

    /// Delete on-disk weights for `model`. Removes the HuggingFace cache
    /// directory the factory uses. Best-effort: filesystem failures are
    /// surfaced through the state store so the user sees a clear error.
    func delete(_ model: LocalModel) {
        guard model.runtime == .mlx, let repo = model.mlxRepo else { return }
        guard let store = stateStore else { return }
        store.apply(.deleting, to: model.id)

        Task { [weak self] in
            guard let self else { return }
            let cacheRoot = MLXInferenceService.huggingFaceCachePath()
                .appendingPathComponent(repo, isDirectory: true)
            do {
                if FileManager.default.fileExists(atPath: cacheRoot.path) {
                    try FileManager.default.removeItem(at: cacheRoot)
                }
                self.inferenceService?.evict(model.id)
                store.apply(.notInstalled, to: model.id)
            } catch {
                self.log.error("[Download] delete \(model.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                store.apply(.failed(message: "Couldn't delete: \(error.localizedDescription)"), to: model.id)
            }
        }
    }

    // MARK: - Private

    private func runDownload(_ model: LocalModel) async throws {
        guard let repo = model.mlxRepo else { return }
        guard let store = stateStore else { return }

        let totalBytes = Int64(model.downloadSizeMB) * 1_000_000

        #if canImport(MLXLLM) && canImport(MLXLMCommon)
        // Drive the load. `loadContainer` downloads weights on the first
        // call; if they're already cached it returns immediately. The
        // progress closure is invoked off the main actor — bridge through
        // `Task { @MainActor }` so SwiftUI re-renders cleanly.
        _ = try await LLMModelFactory.shared.loadContainer(
            configuration: ModelConfiguration(id: repo)
        ) { progress in
            let fraction = max(0.0, min(1.0, progress.fractionCompleted))
            let estimatedDownloaded = Int64(Double(totalBytes) * fraction)
            Task { @MainActor in
                // If the user cancelled in the meantime, drop the update so
                // we don't fight the cancel transition.
                guard let current = self.stateStore?.state(for: model),
                      case .downloading = current else { return }
                self.stateStore?.apply(
                    .downloading(progress: fraction, bytesDownloaded: estimatedDownloaded, bytesTotal: totalBytes),
                    to: model.id
                )
            }
        }

        // Cache size is the source of truth for "what's actually on disk".
        let onDisk = Self.directorySize(at: MLXInferenceService.huggingFaceCachePath()
            .appendingPathComponent(repo, isDirectory: true))
        store.apply(.installed(diskBytes: onDisk > 0 ? onDisk : totalBytes), to: model.id)
        #else
        store.apply(.failed(message: "MLX is not available in this build."), to: model.id)
        #endif
    }

    static func directorySize(at url: URL) -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        guard let enumerator = FileManager.default.enumerator(
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
