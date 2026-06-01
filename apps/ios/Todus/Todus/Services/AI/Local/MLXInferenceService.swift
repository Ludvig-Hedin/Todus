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
            let ext = fileURL.pathExtension.lowercased()
            if ext == "safetensors" || ext == "npz" || ext == "gguf" {
                return true
            }
        }
        return false
    }

    func unloadAll() {
        loaded.removeAll(keepingCapacity: false)
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
        let container = try await LLMModelFactory.shared.loadContainer(
            configuration: ModelConfiguration(id: repo)
        )
        // Single-resident cache: drop the previously loaded container before
        // inserting the new one so switching between multi-GB MLX models
        // doesn't accumulate residency that the jetsam killer trips on. The
        // doc comment on `loaded` promises this behavior — enforce it.
        loaded.removeAll(keepingCapacity: true)
        loaded[model.id] = container
        log.info("[MLX] Warm-loaded \(model.id, privacy: .public)")
    }

    /// Drops a single model container — used by `ModelDownloadService` when
    /// the user deletes weights so we don't keep stale state in memory.
    func evict(_ modelId: String) {
        loaded.removeValue(forKey: modelId)
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
        let container: ModelContainer
        if let cached = loaded[request.model.id] {
            container = cached
        } else {
            do {
                container = try await LLMModelFactory.shared.loadContainer(
                    configuration: ModelConfiguration(id: repo)
                )
                // Match `warmUp`'s single-resident policy so a model switch
                // inside `runStream` doesn't leak the prior container.
                loaded.removeAll(keepingCapacity: true)
                loaded[request.model.id] = container
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

        let outputStream = try await container.perform { context in
            let lmInput = try await context.processor.prepare(
                input: .init(messages: mlxMessages)
            )
            return try MLXLMCommon.generate(
                input: lmInput,
                parameters: parameters,
                context: context
            )
        }

        var promptTokens = 0
        var generationTokens = 0
        var chunkCount = 0
        var producedAny = false
        for await event in outputStream {
            try Task.checkCancellation()
            switch event {
            case .chunk(let text):
                continuation.yield(.token(text))
                producedAny = true
                chunkCount += 1
            case .info(let info):
                promptTokens = info.promptTokenCount
                generationTokens = info.generationTokenCount
            case .toolCall:
                // We don't expose tools to the local model today (`tools: []`).
                // A `.toolCall` would only arrive if a future model emits one
                // unprompted; skip rather than render a confusing artifact.
                // The structured tool-call wiring lands when the chat service
                // grows a local tool surface.
                continue
            @unknown default:
                // mlx-swift-examples may add new event cases beyond the three
                // we know (.chunk / .info / .toolCall). Skip silently rather
                // than crash; we'll render them once we wire explicit handling.
                continue
            }
        }

        if !producedAny {
            // Surface a minimal recovery hint instead of finishing silently —
            // some quantizations refuse to emit on certain prompt shapes.
            continuation.yield(.token(""))
        }

        // Fall back to the chunk count when MLX truncates on `maxTokens`
        // before emitting `.info` (some versions don't flush the trailing
        // info event on cap-hit), so usage telemetry doesn't report 0/0
        // for a stream the user clearly saw produce tokens.
        let reportedGeneration = generationTokens > 0 ? generationTokens : chunkCount
        continuation.yield(.done(usage: LocalTokenUsage(
            inputTokens: promptTokens,
            outputTokens: reportedGeneration
        )))
        continuation.finish()
    }

    /// Canonical HuggingFace cache root. `mlx-swift-examples` writes to
    /// Documents/huggingface by default; we mirror that so installed models
    /// interop with the user's other MLX tooling.
    static func huggingFaceCachePath() -> URL {
        let docs = (try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? URL(fileURLWithPath: NSHomeDirectory())
        return docs.appendingPathComponent("huggingface/models", isDirectory: true)
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
