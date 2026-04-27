import Foundation

// MARK: - VoiceConnectionState

/// Lifecycle states for a live voice session.
enum VoiceConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case failed(String)
}

// MARK: - TranscriptRole

/// Identifies the speaker in a transcript update.
enum TranscriptRole: Sendable {
    case user
    case assistant
}

// MARK: - VoiceSessionEvent

/// Events emitted by a VoiceProvider during a live session.
/// The ViewModel consumes these via the provider's `events` AsyncStream.
enum VoiceSessionEvent: Sendable {
    /// Connection lifecycle change.
    case connectionStateChanged(VoiceConnectionState)
    /// Raw PCM16 audio data to play through speakers.
    case audioReceived(Data)
    /// Transcript text update — `isFinal` marks the end of a complete utterance.
    case transcriptUpdate(role: TranscriptRole, text: String, isFinal: Bool)
    /// The model is requesting a tool/function call.
    case toolCallReceived(id: String, name: String, arguments: String)
    /// The model finished its current turn (done speaking).
    case turnComplete
    /// An error occurred during the session.
    case error(String)
}

// MARK: - VoiceSessionConfig

/// Configuration passed to a VoiceProvider on connect.
/// Provider-agnostic — each implementation maps these fields to its wire format.
struct VoiceSessionConfig {
    /// Model identifier (e.g. "gemini-3.1-flash-live-preview").
    let model: String
    /// System instruction injected at session start.
    let systemInstruction: String
    /// Tool/function declarations as JSON-compatible dictionaries.
    /// Each dictionary follows the OpenAPI-style schema used by both Gemini and OpenAI.
    let tools: [[String: Any]]?
    /// Voice name for text-to-speech (provider-specific, e.g. "Puck" for Gemini).
    let voiceName: String
    /// Audio sample rate for input capture (default 16kHz for Gemini).
    let inputSampleRate: Int
    /// Requested response modalities (e.g. ["AUDIO", "TEXT"]).
    let responseModalities: [String]

    /// Convenience initializer with Gemini Live defaults.
    static func geminiDefault(
        model: String = VoiceModelCatalog.gemini31FlashLiveModel,
        systemInstruction: String,
        tools: [[String: Any]]? = nil,
        voiceName: String = "Puck"
    ) -> Self {
        VoiceSessionConfig(
            model: model,
            systemInstruction: systemInstruction,
            tools: tools,
            voiceName: voiceName,
            inputSampleRate: 16000,
            // Gemini Live only supports ONE response modality per session — sending both
            // "AUDIO" and "TEXT" causes INVALID_ARGUMENT. Pick AUDIO; we still get the
            // text version of what the model said via `outputAudioTranscription`.
            responseModalities: ["AUDIO"]
        )
    }
}

// Sendable conformance — tools contain only JSON-safe primitives.
extension VoiceSessionConfig: @unchecked Sendable {}

// MARK: - VoiceModelCatalog

enum VoiceModelCatalog {
    static let gemini31FlashLiveModel = "gemini-3.1-flash-live-preview"
    static let gemini31FlashLiveDisplayName = "Gemini 3.1 flash live"
}

// MARK: - VoiceProvider Protocol

/// Provider-agnostic interface for a live bidirectional voice session.
///
/// Implementations (e.g. `GeminiLiveProvider`, future `OpenAIRealtimeProvider`)
/// handle vendor-specific WebSocket protocols behind this abstraction.
/// The UI layer (ViewModel) depends only on this protocol.
protocol VoiceProvider: AnyObject, Sendable {
    /// Async stream of events from the provider. Yields until the session ends.
    var events: AsyncStream<VoiceSessionEvent> { get }

    /// Open a live session via the backend WebSocket proxy.
    /// - Parameters:
    ///   - endpoint: The WebSocket URL to connect to (backend proxy, NOT the AI provider directly).
    ///   - authToken: Bearer token for authenticating the WebSocket upgrade request.
    ///   - config: Session configuration (model, system prompt, tools, voice, etc.).
    func connect(endpoint: URL, authToken: String, config: VoiceSessionConfig) async throws

    /// Gracefully close the session.
    func disconnect() async

    /// Send raw PCM16 audio data captured from the microphone.
    func sendAudioPCM(_ data: Data) async throws

    /// Send a text message (for incremental text input during a voice session).
    func sendText(_ text: String) async throws

    /// Send an image for multimodal input.
    func sendImage(_ data: Data, mime: String) async throws

    /// Send the result of a tool call back to the model.
    func sendToolResponse(id: String, name: String, result: String) async throws
}
