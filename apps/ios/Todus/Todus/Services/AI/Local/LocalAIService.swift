import Foundation

// MARK: - LocalAIService
//
// The single abstraction every on-device runtime conforms to (MLX, Apple
// Foundation Models, Ollama on macOS). Mirrors the SSE-shaped events emitted
// by the existing /api/ai/chat path so the chat UI doesn't need to branch.
//
// Design rules:
// • Pure data in, AsyncThrowingStream out. No Combine, no @Observable here.
// • Never touches the network for cloud providers — these implementations are
//   the reason the "no plan credits" guarantee is architectural rather than a
//   billing flag.
// • Tool calls are surfaced as structured events the chat service can handle
//   the same way it handles cloud tool calls today. Models that don't support
//   tool use should just never emit `.toolCall`; callers gate that off
//   `LocalModel.supportsToolUse` before issuing tool-eligible prompts.

/// Minimal message shape the local runtimes accept. Intentionally loose so
/// any caller (cloud chat service, mail-assistant flow, future automation)
/// can adapt without coupling to the cloud chat's richer message struct.
struct LocalChatMessage: Hashable {
    enum Role: String, Hashable {
        case system
        case user
        case assistant
        case tool
    }

    let role: Role
    let content: String
    /// For tool-result messages: the tool name the assistant called.
    let toolName: String?
    /// For tool-result messages: the id the assistant used to address the call.
    let toolCallId: String?

    init(role: Role, content: String, toolName: String? = nil, toolCallId: String? = nil) {
        self.role = role
        self.content = content
        self.toolName = toolName
        self.toolCallId = toolCallId
    }
}

/// Per-turn streaming events emitted by every local runtime. Shape matches
/// what AIChatService.decodeSSELine produces from the cloud path so the chat
/// services can reuse their existing rendering pipeline.
enum LocalStreamEvent: Hashable {
    /// Visible assistant text chunk. Multiple `.token` events per turn.
    case token(String)
    /// Hidden chain-of-thought / reasoning text. Some runtimes (Qwen 3 with
    /// thinking, future Apple FM) emit this separately; UI shows it folded.
    case reasoning(String)
    /// Structured tool call the assistant wants the host to execute. The host
    /// is responsible for running the tool and feeding a `.tool`-role message
    /// back into the next `stream(...)` invocation.
    case toolCall(id: String, name: String, argumentsJSON: String)
    /// Final event of the turn. Always emitted exactly once before the stream
    /// completes (even on cancellation we try to emit this with zero usage).
    case done(usage: LocalTokenUsage)
}

struct LocalTokenUsage: Hashable {
    /// Input tokens billed by the runtime. Local runtimes still surface this
    /// for telemetry / debug, but it never reaches the billing service.
    let inputTokens: Int
    let outputTokens: Int

    static let zero = LocalTokenUsage(inputTokens: 0, outputTokens: 0)
}

/// Errors any local runtime may throw. Prefer typed cases over `NSError` so
/// the UI can match on intent and produce actionable copy.
enum LocalAIError: Error, LocalizedError {
    /// The selected model is not installed (weights aren't on disk yet).
    case modelNotInstalled(modelId: String)
    /// The model is installed but the runtime can't load it (corrupt weights,
    /// quantization mismatch, OS version too old, etc.).
    case modelLoadFailed(modelId: String, underlying: Error?)
    /// The runtime is unavailable on this device — Apple FM on iOS 25, MLX
    /// on Intel Mac, Ollama daemon not running, etc.
    case runtimeUnavailable(reason: String)
    /// The host requested a tool call but the model can't reliably emit them.
    /// Surface this so the chat service can prompt the user to fall back to
    /// the cloud model for the current turn.
    case toolUseUnsupported
    /// The inference loop hit an internal error mid-stream.
    case generationFailed(underlying: Error?)
    /// User cancelled the stream (e.g. tapped Stop in the chat UI).
    case cancelled

    var errorDescription: String? {
        switch self {
        case .modelNotInstalled(let id):
            return "Model \(id) isn't installed yet. Open Settings → Local Models to download it."
        case .modelLoadFailed(let id, let underlying):
            return "Couldn't load \(id)." + (underlying.map { " \($0.localizedDescription)" } ?? "")
        case .runtimeUnavailable(let reason):
            return reason
        case .toolUseUnsupported:
            return "This model can't run tools. Use a cloud model for this turn."
        case .generationFailed(let underlying):
            return underlying?.localizedDescription ?? "On-device generation failed."
        case .cancelled:
            return nil
        }
    }
}

/// Inputs every runtime accepts for a single chat turn. Mirrors the request
/// shape AIChatService already builds for the cloud path so wiring the two is
/// a switch on `LocalModel.runtime`.
struct LocalChatRequest {
    let model: LocalModel
    let messages: [LocalChatMessage]
    /// Soft cap on output tokens. Each runtime may clamp this further to the
    /// model's actual context window.
    let maxOutputTokens: Int
    /// Sampling temperature, 0...1. Defaults reasonable for chat.
    let temperature: Double
    /// When true and the runtime supports it, emit `.reasoning` events for
    /// chain-of-thought (Qwen 3 thinking mode, etc).
    let enableThinking: Bool
    /// Optional structured tools the assistant may call. Ignored by runtimes
    /// where `model.supportsToolUse == false`; the chat service is expected
    /// to gate these off the model in advance and surface a fallback prompt.
    let tools: [LocalTool]

    init(
        model: LocalModel,
        messages: [LocalChatMessage],
        maxOutputTokens: Int = 1024,
        temperature: Double = 0.7,
        enableThinking: Bool = false,
        tools: [LocalTool] = []
    ) {
        self.model = model
        self.messages = messages
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.enableThinking = enableThinking
        self.tools = tools
    }
}

/// Loose tool descriptor — the fields we need to drive both function-calling
/// (most MLX models) and Apple FM tools. JSON schema is passed through as a
/// raw string so we don't drag in a JSONSchema dependency for v1.
struct LocalTool: Hashable {
    let name: String
    let description: String
    let parametersJSONSchema: String
}

// MARK: - Protocol

/// Concrete runtimes (`MLXInferenceService`, `AppleFoundationModelService`,
/// `OllamaInferenceService`) implement this. The dispatch in `AIChatService`
/// / `MacAIChatService` picks the right one off `LocalModel.runtime`.
///
/// The protocol is `@MainActor` because every concrete runtime is also
/// main-actor (they own model containers / probe state and are read by
/// SwiftUI views). Marking the protocol matches that constraint and avoids
/// "crosses into main actor-isolated code" diagnostics under Swift 6.
@MainActor
protocol LocalAIService: AnyObject {
    /// Streams a single chat turn. The stream completes (or throws) exactly
    /// once. Cancellation is honored via task cancellation.
    func stream(_ request: LocalChatRequest) -> AsyncThrowingStream<LocalStreamEvent, Error>

    /// True if the model's weights are present on disk and the runtime can
    /// load them right now. Apple FM returns true whenever the OS exposes
    /// the framework; Ollama returns true if the daemon lists the tag.
    func isReady(for model: LocalModel) -> Bool

    /// Best-effort eviction of any in-memory model state. Called on memory
    /// warning (iOS) or thermal pressure (macOS). Safe to call repeatedly.
    func unloadAll()
}

// MARK: - Default no-op fallback

/// Used by callers that need a non-optional dependency before the real
/// runtimes are wired in (Phases 2/3). Always reports "not ready" and
/// throws `runtimeUnavailable` on `stream(...)` so the chat service falls
/// back to the cloud path with a clear message.
@MainActor
final class UnimplementedLocalAIService: LocalAIService {
    func stream(_ request: LocalChatRequest) -> AsyncThrowingStream<LocalStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(
                throwing: LocalAIError.runtimeUnavailable(
                    reason: "On-device inference isn't available in this build yet."
                )
            )
        }
    }

    func isReady(for model: LocalModel) -> Bool { false }

    func unloadAll() {}
}
