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
        // "Ready" without a load = the weights are on disk somewhere the
        // factory will find them. Conservative check: the canonical HF cache
        // path under our app's documents dir contains the repo.
        let candidate = Self.huggingFaceCachePath()
            .appendingPathComponent(repo, isDirectory: true)
        return FileManager.default.fileExists(atPath: candidate.path)
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
                loaded[request.model.id] = container
            } catch {
                continuation.finish(throwing: LocalAIError.modelLoadFailed(
                    modelId: request.model.id, underlying: error
                ))
                return
            }
        }

        // MLX expects a `[Chat.Message]` for the structured-chat path. The
        // processor turns these into the model-specific dict shape. Tool
        // results from earlier turns get the dedicated `.tool` role; most
        // chat templates that ignore it just skip it without erroring.
        let mlxMessages: [Chat.Message] = request.messages.map { msg in
            switch msg.role {
            case .system:    return .system(msg.content)
            case .user:      return .user(msg.content)
            case .assistant: return .assistant(msg.content)
            case .tool:      return .tool(msg.content)
            }
        }

        let parameters = GenerateParameters(
            temperature: Float(request.temperature)
        )

        let outputStream = try await container.perform { context in
            let lmInput = try await context.processor.prepare(
                input: UserInput(chat: mlxMessages)
            )
            return try MLXLMCommon.generate(
                input: lmInput,
                parameters: parameters,
                context: context
            )
        }

        var promptTokens = 0
        var generationTokens = 0
        var producedAny = false
        var maxTokenBudget = request.maxOutputTokens
        for await event in outputStream {
            try Task.checkCancellation()
            switch event {
            case .chunk(let text):
                continuation.yield(.token(text))
                producedAny = true
                generationTokens += 1
                maxTokenBudget -= 1
                if maxTokenBudget <= 0 {
                    continuation.yield(.done(usage: LocalTokenUsage(
                        inputTokens: promptTokens, outputTokens: generationTokens
                    )))
                    continuation.finish()
                    return
                }
            case .info(let info):
                promptTokens = info.promptTokenCount
                generationTokens = info.generationTokenCount
            case .toolCall(let call):
                // MLX surfaces structured tool calls when the model uses the
                // chat template's tool format. We don't yet support local
                // tool execution (Phase 7 follow-up); forward as a token so
                // the user at least sees the model's intent.
                continuation.yield(.token("[tool: \(call.function.name)]"))
            }
        }

        if !producedAny {
            // Surface a minimal recovery hint instead of finishing silently —
            // some quantizations refuse to emit on certain prompt shapes.
            continuation.yield(.token(""))
        }

        continuation.yield(.done(usage: LocalTokenUsage(
            inputTokens: promptTokens,
            outputTokens: generationTokens
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
