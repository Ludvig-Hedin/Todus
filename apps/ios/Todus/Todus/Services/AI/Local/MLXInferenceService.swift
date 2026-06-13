import Foundation
import OSLog

#if canImport(MLXLLM) && canImport(MLXLMCommon)
import MLXLLM
import MLXLMCommon
#endif

// MARK: - MLXInferenceService
//
// Streams chat completions from MLX-quantized weights running on Apple Silicon
// (GPU + Neural Engine). The implementation defers to `mlx-swift-examples`'s
// `LLMModelFactory` for HuggingFace download + load + tokenization, then wraps
// `MLXLMCommon.generate(...)` in our `LocalAIService` shape.
//
// Why we use `LLMModelFactory.loadContainer` instead of running our own loader:
//   • The factory already mirrors the HuggingFace Hub cache layout the rest of
//     the MLX ecosystem uses, so models pulled here interop with the user's
//     own MLX experiments.
//   • It handles tokenizer config, weight sharding, and quantization metadata
//     (which would be ~500 lines of code to redo correctly).
//   • The download progress callback is exactly what `ModelDownloadService`
//     forwards into `LocalModelStateStore`, so there's no duplicate work.

#if canImport(MLXLLM) && canImport(MLXLMCommon)

@MainActor
final class MLXInferenceService: LocalAIService {
    /// Cached `ModelContainer`s keyed by model id. We keep the most recently
    /// used model resident; calling `unloadAll()` (memory pressure / thermal)
    /// drops everything.
    private var loaded: [String: ModelContainer] = [:]
    /// In-flight `loadContainer` calls keyed by model id. Coalesces concurrent
    /// `warmUp(modelA)` + `runStream(modelA)` (or two concurrent picker
    /// pre-warms) into a single download/load — without this, both paths
    /// see `loaded[id] == nil`, both `await` the factory, and we pay the
    /// disk/CPU/memory cost twice for the same weights. Each entry carries
    /// a monotonic `seq` so the reaper Task only clears its own slot —
    /// without that tag, a slow reaper from a cancelled load would clear
    /// the entry of a fresh load that started after `evict`.
    private struct InflightEntry {
        let seq: UInt64
        let task: Task<ModelContainer, Error>
    }
    private var inflight: [String: InflightEntry] = [:]
    private var inflightSeq: UInt64 = 0
    /// The most recent model id any caller asked to make resident — set on
    /// `warmUp` / `runStream` entry. The reaper consults this so a slow
    /// load for model A that finishes after the user switched to B can't
    /// clobber `loaded = [B]` back to `loaded = [A]`. Without this, the
    /// `loaded` map would lag the user's active selection across cross-
    /// model load races.
    private var lastRequestedModelId: String?
    private let log = Logger(subsystem: "com.todus.ios", category: "MLXInferenceService")

    func isReady(for model: LocalModel) -> Bool {
        guard model.runtime == .mlx, let repo = model.mlxRepo else { return false }
        // "Ready" without a load = real weights are on disk where the factory
        // will find them. Mirror `LocalModelStateStore.hasWeightFile` so a
        // partial / failed download isn't reported as ready (which would
        // crash MLX on first turn).
        let fm = FileManager.default
        let candidate = Self.huggingFaceCachePath()
            .appendingPathComponent(repo, isDirectory: true)
        guard fm.fileExists(atPath: candidate.path) else { return false }
        guard let enumerator = fm.enumerator(
            at: candidate,
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

    func unloadAll() {
        loaded.removeAll(keepingCapacity: false)
        lastRequestedModelId = nil
        // Cancel in-flight loads. Slot cleanup is handled by each load's
        // reaper Task once the underlying work settles. A fresh caller
        // arriving while the cancelled task is still grinding hits
        // `loadCoalesced`'s `isCancelled` guard and spawns its own task
        // rather than awaiting the cancelled one. Clearing
        // `lastRequestedModelId` also blocks any reaper from re-installing
        // a model after the user-driven unload.
        for entry in inflight.values { entry.task.cancel() }
        log.info("[MLX] Unloaded all model containers (memory pressure / explicit reset)")
    }

    func stream(_ request: LocalChatRequest) -> AsyncThrowingStream<LocalStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    try await self.runStream(request, continuation: continuation)
                } catch is CancellationError {
                    continuation.finish(throwing: LocalAIError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Pre-loads a model so the first chat turn doesn't pay the load latency.
    /// Surfaced by the chat service when the user picks an MLX model in the
    /// model picker. Safe to call repeatedly; idempotent.
    func warmUp(_ model: LocalModel) async throws {
        guard model.runtime == .mlx, let repo = model.mlxRepo else { return }
        if loaded[model.id] != nil { return }
        lastRequestedModelId = model.id
        let container = try await loadCoalesced(modelId: model.id, repo: repo)
        // Belt-and-suspenders: also publish directly in the caller's frame.
        // The reaper writes `loaded` too, but Swift concurrency doesn't
        // guarantee the reaper runs before this resumption. Gate on
        // `lastRequestedModelId == model.id` so an A→B switch during
        // the await doesn't have A's resumption clobber B's freshly
        // resident container.
        if lastRequestedModelId == model.id {
            loaded = [model.id: container]
        }
        log.info("[MLX] Warm-loaded \(model.id, privacy: .public)")
    }

    /// Coalesce concurrent loads for the same model id so we only pay the
    /// disk/CPU/memory cost once, and atomically swap the single-resident
    /// `loaded` cache once we have a container. The inflight slot is freed
    /// when the underlying load actually finishes (not when this caller's
    /// frame exits) — a caller cancelled mid-await otherwise leaves the
    /// slot empty while the unstructured Task keeps running, and a fresh
    /// caller arriving after the cancellation spawns a duplicate load.
    private func loadCoalesced(modelId: String, repo: String) async throws -> ModelContainer {
        // Reuse an in-flight task ONLY if it hasn't been cancelled. After
        // `evict` cancels an entry but leaves the slot, a fresh caller
        // would otherwise inherit the cancellation and surface a
        // `LocalAIError.cancelled` they never requested.
        // TODO(bug-hunt): Residual cancellation race — if evict()/unloadAll() cancels
        // this entry's task AFTER the !isCancelled check passes but while
        // `await pending.task.value` is suspended, this coalesced caller still
        // surfaces a CancellationError it never requested. Consider having
        // evict/unloadAll synchronously removeValue(forKey:) the slot they cancel,
        // or retrying a fresh load when a non-cancelled caller catches CancellationError.
        if let pending = inflight[modelId], !pending.task.isCancelled {
            return try await pending.task.value
        }
        inflightSeq &+= 1
        let seq = inflightSeq
        let task: Task<ModelContainer, Error> = Task {
            try await LLMModelFactory.shared.loadContainer(
                configuration: ModelConfiguration(id: repo)
            )
        }
        inflight[modelId] = InflightEntry(seq: seq, task: task)
        // Reaper Task fires when this specific load finishes (success or
        // failure). The `seq` check appears in BOTH the publish AND clear
        // paths so a stale reaper can't:
        //   - overwrite `loaded` with its container (would evict whatever
        //     model the user has switched to since this load started);
        //   - clear a fresher load's inflight slot.
        // `!task.isCancelled` further blocks a cancelled load from
        // resurrecting its model — `LLMModelFactory.loadContainer` may
        // succeed despite the cancel since cooperative cancellation is
        // advisory, so we must filter on the task's final cancelled flag.
        Task { [weak self] in
            let result = await task.result
            guard let self else { return }
            let stillCurrent = self.inflight[modelId]?.seq == seq
            // `lastRequestedModelId` filter: a slow A→B switch where A's
            // load resolves after B's blocks A from clobbering `loaded = [B]`.
            // The seq check alone only protects against same-modelId races.
            if case .success(let container) = result,
               stillCurrent,
               !task.isCancelled,
               self.lastRequestedModelId == modelId {
                self.loaded = [modelId: container]
            }
            if stillCurrent {
                self.inflight.removeValue(forKey: modelId)
            }
        }
        return try await task.value
    }

    /// Drops a single model container — used by `ModelDownloadService` when
    /// the user deletes weights so we don't keep stale state in memory.
    func evict(_ modelId: String) {
        loaded.removeValue(forKey: modelId)
        // Cancel the in-flight load if any. Reaper drops the slot when the
        // underlying task settles; a fresh caller skips a cancelled entry
        // via `loadCoalesced`'s isCancelled guard.
        inflight[modelId]?.task.cancel()
        // If the evicted model is the one the user most recently asked to
        // make resident, clear `lastRequestedModelId` so a late-resolving
        // load doesn't re-install the deleted weights.
        if lastRequestedModelId == modelId { lastRequestedModelId = nil }
    }

    // MARK: - Private

    private func runStream(
        _ request: LocalChatRequest,
        continuation: AsyncThrowingStream<LocalStreamEvent, Error>.Continuation
    ) async throws {
        guard request.model.runtime == .mlx, let repo = request.model.mlxRepo else {
            continuation.finish(throwing: LocalAIError.runtimeUnavailable(
                reason: "MLX can't run \(request.model.displayName)."
            ))
            return
        }

        // Lazy-load. If `ModelDownloadService` already pulled the weights this
        // is fast; otherwise the factory downloads on demand and the user sees
        // a spinner via `LocalModelStateStore` (download is also tracked
        // separately by ModelDownloadService when the user explicitly opts in).
        lastRequestedModelId = request.model.id
        let container: ModelContainer
        if let cached = loaded[request.model.id] {
            container = cached
        } else {
            do {
                container = try await loadCoalesced(modelId: request.model.id, repo: repo)
                // Belt-and-suspenders: also publish directly so a follow-up
                // turn doesn't spawn a redundant load if the reaper hasn't
                // run yet. Gate on `lastRequestedModelId` so an A→B switch
                // during the load doesn't clobber B's resident container.
                if lastRequestedModelId == request.model.id {
                    loaded = [request.model.id: container]
                }
            } catch is CancellationError {
                // Re-throw so the outer `stream(...)` handler maps to
                // `LocalAIError.cancelled`. Calling `continuation.finish`
                // here would emit the raw `CancellationError` to consumers
                // and diverge from the `Task.checkCancellation()` path
                // inside the stream loop, which throws out and gets
                // remapped — same logical condition, two error types.
                throw CancellationError()
            } catch {
                continuation.finish(throwing: LocalAIError.modelLoadFailed(
                    modelId: request.model.id, underlying: error
                ))
                return
            }
        }

        // MLX's processor accepts a `[[String: String]]` shape that mirrors the
        // HuggingFace chat template. Using the plain-dict shape (over the
        // `[Chat.Message]` API) sidesteps a Swift 6 Sendable gap in mlx-swift-
        // examples 2.29.1 — closures capturing `Chat.Message` arrays fail to
        // compile under strict concurrency. Tool results from earlier turns
        // collapse into a `user` message so non-tool chat templates don't
        // crash on an unknown role.
        let mlxMessages: [[String: String]] = request.messages.map { msg in
            switch msg.role {
            case .system:    return ["role": "system", "content": msg.content]
            case .user:      return ["role": "user", "content": msg.content]
            case .assistant: return ["role": "assistant", "content": msg.content]
            case .tool:      return ["role": "user", "content": "[tool result] \(msg.content)"]
            }
        }

        // Use the native token cap on `GenerateParameters` instead of decrementing
        // a per-`.chunk` counter — `.chunk` yields a detokenized string that can
        // span multiple tokens, so a manual `-= 1` over-runs the budget by 2-4×
        // on common tokenizers. Guard against a zero / negative caller value so
        // we don't pin generation at 0 tokens.
        // Build the parameters struct fully before handing it to the @Sendable closure.
        // Capturing a mutable `var` here triggers Swift 6's strict-concurrency check.
        let parameters: GenerateParameters = {
            var p = GenerateParameters(temperature: Float(request.temperature))
            p.maxTokens = max(request.maxOutputTokens, 1)
            return p
        }()

        // Iterate the stream INSIDE `container.perform` so `MLXArray`-backed
        // detokenizer state can't be touched after the closure returns.
        // `ModelContainer.perform`'s docstring explicitly requires callers
        // to "eval any `MLXArray` before returning as `MLXArray` is not
        // `Sendable`" — returning the AsyncStream out and iterating it on
        // the surrounding for-await loop is the documented foot-gun that
        // surfaces as nondeterministic crashes on long generations under
        // memory pressure. Collect counts via a return value so we don't
        // need to mutate captures from the @Sendable closure.
        struct StreamStats: Sendable {
            var promptTokens = 0
            var generationTokens = 0
        }
        let stats: StreamStats = try await container.perform { context in
            let lmInput = try await context.processor.prepare(
                input: .init(messages: mlxMessages)
            )
            let outputStream = try MLXLMCommon.generate(
                input: lmInput,
                parameters: parameters,
                context: context
            )
            var local = StreamStats()
            for await event in outputStream {
                try Task.checkCancellation()
                switch event {
                case .chunk(let text):
                    continuation.yield(.token(text))
                case .info(let info):
                    local.promptTokens = info.promptTokenCount
                    local.generationTokens = info.generationTokenCount
                case .toolCall:
                    // We don't expose tools to the local model today
                    // (`tools: []`). A `.toolCall` would only arrive if a
                    // future model emits one unprompted; skip rather than
                    // render a confusing artifact. The structured tool-call
                    // wiring lands when the chat service grows a local
                    // tool surface.
                    continue
                @unknown default:
                    // mlx-swift-examples may add new event cases beyond the
                    // three we know (.chunk / .info / .toolCall). Skip
                    // silently rather than crash; we'll render them once we
                    // wire explicit handling.
                    continue
                }
            }
            return local
        }

        // Report `.info`-sourced counts only. `.chunk` yields detokenized
        // strings that can span multiple tokens (see the `maxTokens` comment
        // above), so chunk-counting `outputTokens` would undercount by
        // 2-4× on BPE tokenizers and silently corrupt billing telemetry.
        // If MLX truncated on `maxTokens` without flushing `.info`, surface
        // 0/0 — callers that care about per-stream cost can treat zeros as
        // "unknown" and avoid charging on a half-measured stream.
        continuation.yield(.done(usage: LocalTokenUsage(
            inputTokens: stats.promptTokens,
            outputTokens: stats.generationTokens
        )))
        continuation.finish()
    }

    /// Canonical HuggingFace cache root. `mlx-swift-examples` writes to
    /// Documents/huggingface by default; we mirror that so installed models
    /// interop with the user's other MLX tooling. Excludes the directory
    /// from iCloud backup the first time it's created — multi-GB weight
    /// files would otherwise balloon the user's iCloud backup quota,
    /// slow restores, and (on iOS) get aggressively reaped under storage
    /// pressure with no indication to the user.
    static func huggingFaceCachePath() -> URL {
        let fm = FileManager.default
        let docs = (try? fm.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? URL(fileURLWithPath: NSHomeDirectory())
        let root = docs.appendingPathComponent("huggingface", isDirectory: true)
        if !fm.fileExists(atPath: root.path) {
            try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        }
        // Apply / re-apply `isExcludedFromBackup` outside the "first-create"
        // gate so a directory created by a prior app version (when the
        // exclusion call wasn't yet in place) gets backfilled on the next
        // run — otherwise multi-GB model weights would still end up in
        // iCloud backups for any user upgrading from such a version.
        var mutable = root
        let alreadyExcluded = (try? mutable.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) ?? false
        if !alreadyExcluded {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? mutable.setResourceValues(values)
        }
        // Create the `models/` leaf too so consumers can immediately
        // enumerate / write under the returned URL without depending on
        // `LocalModelStateStore.modelsDirectory` having run first.
        let modelsDir = root.appendingPathComponent("models", isDirectory: true)
        if !fm.fileExists(atPath: modelsDir.path) {
            try? fm.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        }
        return modelsDir
    }
}

#else

// MLX modules unavailable in this build configuration. Provides a stub that
// reports unavailable, so callers can still link the file (e.g. when building
// for the iOS simulator without MLX).
@MainActor
final class MLXInferenceService: LocalAIService {
    func isReady(for model: LocalModel) -> Bool { false }
    func unloadAll() {}
    func warmUp(_ model: LocalModel) async throws {}
    func evict(_ modelId: String) {}
    func stream(_ request: LocalChatRequest) -> AsyncThrowingStream<LocalStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: LocalAIError.runtimeUnavailable(
                reason: "MLX is not available in this build."
            ))
        }
    }
    static func huggingFaceCachePath() -> URL {
        let docs = (try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? URL(fileURLWithPath: NSHomeDirectory())
        return docs.appendingPathComponent("huggingface/models", isDirectory: true)
    }
}

#endif
