import Foundation

// MARK: - GeminiLiveProvider

/// Implements the `VoiceProvider` protocol using Gemini Live's bidirectional
/// WebSocket API (`BidiGenerateContent`).
///
/// Wire protocol:
/// 1. Client sends a `setup` message (model, system instruction, tools).
/// 2. Server responds with `setupComplete`.
/// 3. Client sends `realtimeInput.audio` with base64 PCM16 @ 16kHz.
/// 4. Client may also send `realtimeInput.text` for mid-session text input.
/// 5. Server sends `serverContent` with modelTurn parts (text / audio) and transcriptions.
/// 6. Tool calls arrive as `toolCall`, client responds with `toolResponse`.
/// 7. `turnComplete` signals the model finished its current response.
final class GeminiLiveProvider: VoiceProvider, @unchecked Sendable {

    // MARK: - VoiceProvider conformance

    var events: AsyncStream<VoiceSessionEvent> {
        eventStream
    }

    // MARK: - Private state

    private var webSocketTask: URLSessionWebSocketTask?
    /// Stored so we can invalidate it in disconnect() to avoid URLSession leaks.
    private var webSocketSession: URLSession?
    private var receiveTask: Task<Void, Never>?
    /// Fires if Gemini doesn't reply with `setupComplete` within the timeout, so the UI
    /// doesn't sit on a spinner forever when the upstream silently drops the setup.
    private var setupTimeoutTask: Task<Void, Never>?
    private var eventContinuation: AsyncStream<VoiceSessionEvent>.Continuation?
    /// Mutable: recreated on each connect() so the provider isn't single-use.
    private var eventStream: AsyncStream<VoiceSessionEvent>
    /// Last server-sent error message (from the proxy's error JSON, or a Gemini error
    /// envelope). Used so that when the WebSocket then closes, the surfaced reason is
    /// descriptive instead of a generic NSURLError -1011.
    /// Guarded by `stateLock` — touched from receive loop, timeout task, and connect().
    private var _lastServerError: String?
    /// Marked true once we've emitted .connected. Lets us suppress the setup timeout.
    /// Guarded by `stateLock`.
    private var _didReachSetupComplete = false

    /// Protects `_lastServerError` and `_didReachSetupComplete` from concurrent access
    /// across the receive loop, timeout task, and connect() / cleanup paths.
    private let stateLock = NSLock()

    private var lastServerError: String? {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _lastServerError }
        set { stateLock.lock(); defer { stateLock.unlock() }; _lastServerError = newValue }
    }

    private var didReachSetupComplete: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _didReachSetupComplete }
        set { stateLock.lock(); defer { stateLock.unlock() }; _didReachSetupComplete = newValue }
    }

    /// Atomically claim the "setup didn't complete in time" path so the timeout task
    /// and the receive loop can't both win and emit conflicting events. Returns true
    /// if the caller now owns the failure path; false if setupComplete already landed.
    private func claimSetupTimeout() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !_didReachSetupComplete else { return false }
        // Mark as "complete" so a late setupComplete from the receive loop is a no-op.
        _didReachSetupComplete = true
        return true
    }

    /// Serial queue for WebSocket sends to avoid interleaved writes.
    private let sendQueue = DispatchQueue(label: "com.todus.geminiLive.send", qos: .userInitiated)

    init() {
        var continuation: AsyncStream<VoiceSessionEvent>.Continuation?
        self.eventStream = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
    }

    // MARK: - Connect

    func connect(endpoint: URL, authToken: String, config: VoiceSessionConfig) async throws {
        // Recreate event stream so provider is reusable after disconnect
        var continuation: AsyncStream<VoiceSessionEvent>.Continuation?
        self.eventStream = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
        didReachSetupComplete = false
        lastServerError = nil

        yield(.connectionStateChanged(.connecting))

        // Connect to the backend WebSocket proxy (NOT directly to Gemini).
        // The proxy handles the Gemini API key server-side — it never reaches the client.
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        self.webSocketSession = session
        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        // Start receive loop before sending setup (server may send setupComplete quickly)
        startReceiveLoop()

        // Send the setup message; clean up if it fails
        let setupJSON = buildSetupMessage(config: config)
        do {
            try await sendJSON(setupJSON)
        } catch {
            cleanupConnection()
            throw error
        }

        // If Gemini doesn't reply with setupComplete within 15s, the session is hung —
        // surface a real error so the UI doesn't sit on a spinner forever. Most causes:
        // bad model name, malformed setup payload, or a silent upstream drop.
        scheduleSetupTimeout()
    }

    private func scheduleSetupTimeout() {
        setupTimeoutTask?.cancel()
        setupTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15 * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            // Atomic claim so a setupComplete arriving in the receive loop right now
            // can't slip past and cause both .connected and .failed to fire.
            guard self.claimSetupTimeout() else { return }
            let reason = self.lastServerError
                ?? "Voice session did not start (no response from voice provider after 15s)."
            self.yield(.error(reason))
            self.yield(.connectionStateChanged(.failed(reason)))
            self.cleanupConnection()
        }
    }

    // MARK: - Disconnect

    func disconnect() async {
        cleanupConnection()
        yield(.connectionStateChanged(.disconnected))
        eventContinuation?.finish()
        eventContinuation = nil
    }

    /// Shared cleanup: cancels receive loop, closes WebSocket, invalidates URLSession.
    /// Does NOT finish the event continuation (disconnect does that separately).
    private func cleanupConnection() {
        setupTimeoutTask?.cancel()
        setupTimeoutTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        webSocketSession?.invalidateAndCancel()
        webSocketSession = nil
    }

    // MARK: - Send Audio

    func sendAudioPCM(_ data: Data) async throws {
        guard webSocketTask != nil else { throw VoiceProviderError.notConnected }
        let base64 = data.base64EncodedString()
        let message: [String: Any] = [
            "realtimeInput": [
                "audio": [
                    "data": base64,
                    "mimeType": "audio/pcm;rate=16000"
                ]
            ]
        ]
        try await sendJSON(message)
    }

    // MARK: - Send Text

    func sendText(_ text: String) async throws {
        guard webSocketTask != nil else { throw VoiceProviderError.notConnected }
        let message: [String: Any] = [
            "realtimeInput": [
                "text": text
            ]
        ]
        try await sendJSON(message)
    }

    // MARK: - Send Image

    func sendImage(_ data: Data, mime: String) async throws {
        guard webSocketTask != nil else { throw VoiceProviderError.notConnected }
        let base64 = data.base64EncodedString()
        let message: [String: Any] = [
            "realtimeInput": [
                "media": [
                    "data": base64,
                    "mimeType": mime
                ]
            ]
        ]
        try await sendJSON(message)
    }

    // MARK: - Send Tool Response

    func sendToolResponse(id: String, name: String, result: String) async throws {
        guard webSocketTask != nil else { throw VoiceProviderError.notConnected }
        let message: [String: Any] = [
            "toolResponse": [
                "functionResponses": [
                    [
                        "id": id,
                        "name": name,
                        "response": ["result": result]
                    ]
                ]
            ]
        ]
        try await sendJSON(message)
    }

    // MARK: - Setup Message

    private func buildSetupMessage(config: VoiceSessionConfig) -> [String: Any] {
        // Per the BidiGenerateContent proto: GenerationConfig holds responseModalities and
        // speechConfig; inputAudioTranscription / outputAudioTranscription are SIBLINGS of
        // generationConfig inside setup (not nested under it).
        let generationConfig: [String: Any] = [
            "responseModalities": config.responseModalities,
            "speechConfig": [
                "voiceConfig": [
                    "prebuiltVoiceConfig": [
                        "voiceName": config.voiceName
                    ]
                ]
            ]
        ]

        var setupBody: [String: Any] = [
            "model": config.model,
            "generationConfig": generationConfig,
            "systemInstruction": [
                "parts": [["text": config.systemInstruction]]
            ],
            // Empty objects = "enabled with defaults" per the spec.
            "inputAudioTranscription": [String: Any](),
            "outputAudioTranscription": [String: Any](),
        ]

        // Add tool declarations if provided
        if let tools = config.tools, !tools.isEmpty {
            setupBody["tools"] = [["functionDeclarations": tools]]
        }

        // CRITICAL: the wire-level wrapper is `setup`, not `config`. The previous version
        // sent `{"config": {...}}` — Gemini's oneof discriminator silently treated the
        // message as empty, the session held open waiting for a real setup, and the client
        // sat on a spinner forever with no error to surface.
        return ["setup": setupBody]
    }

    // MARK: - Receive Loop

    private func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let task = self.webSocketTask else { break }
                do {
                    let message = try await task.receive()
                    switch message {
                    case .string(let text):
                        self.handleServerMessage(text)
                    case .data(let data):
                        // Gemini sends JSON as string, but handle data just in case
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleServerMessage(text)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    if !Task.isCancelled {
                        // Prefer a server-sent error message (from the proxy's error JSON) over
                        // the generic URLError. The backend sends `{ "error": "...", "message": "..." }`
                        // immediately before closing the socket on auth/credit/upstream failures,
                        // which gives the user a real reason instead of "bad server response".
                        let task = self.webSocketTask
                        // Capture close info from URLSession before nilling out the task.
                        let closeCode = task?.closeCode ?? .invalid
                        let closeReason = task?.closeReason
                            .flatMap { String(data: $0, encoding: .utf8) }
                            .flatMap { $0.isEmpty ? nil : $0 }

                        self.webSocketTask?.cancel(with: .abnormalClosure, reason: nil)
                        self.webSocketTask = nil
                        self.webSocketSession?.invalidateAndCancel()
                        self.webSocketSession = nil

                        let surfaced = self.lastServerError
                            ?? closeReason
                            ?? Self.describeCloseCode(closeCode)
                            ?? error.localizedDescription
                        self.lastServerError = nil
                        self.yield(.error(surfaced))
                        self.yield(.connectionStateChanged(.failed(surfaced)))
                    }
                    break
                }
            }
        }
    }

    /// Maps URLSessionWebSocketTask.CloseCode to a human-readable hint for cases where
    /// the server didn't supply a reason. .invalid is returned when the handshake never
    /// produced a close frame at all (the typical "bad server response" path).
    private static func describeCloseCode(_ code: URLSessionWebSocketTask.CloseCode) -> String? {
        switch code {
        case .invalid:
            return "Could not reach the voice server. Check your connection and try again."
        case .normalClosure, .goingAway:
            return nil
        case .protocolError:
            return "Voice connection protocol error."
        case .unsupportedData:
            return "Voice server sent unsupported data."
        case .policyViolation:
            return "Voice connection rejected by server policy."
        case .messageTooBig:
            return "Voice message too large."
        case .internalServerError:
            return "Voice server error. Please try again."
        default:
            return "Voice connection closed (code \(code.rawValue))."
        }
    }

    // MARK: - Message Parsing

    private func handleServerMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        // Proxy error envelope — backend sends `{ "error": "<tag>", "message": "<reason>" }`
        // immediately before closing on auth/credit/upstream failures. Surface it
        // immediately instead of waiting for a later close event because some network
        // failure paths never deliver a useful close reason back to URLSession.
        if let _ = json["error"] as? String {
            let message = (json["message"] as? String) ?? "Voice service error"
            lastServerError = message
            yield(.error(message))
            yield(.connectionStateChanged(.failed(message)))
            cleanupConnection()
            return
        }

        // Gemini-format error envelope: `{ "error": { "code": N, "message": "...", "status": "..." } }`.
        // Surfaced directly because Gemini may close the socket cleanly afterwards with no extra info.
        if let errorObj = json["error"] as? [String: Any] {
            let msg = (errorObj["message"] as? String)
                ?? (errorObj["status"] as? String)
                ?? "Voice provider error"
            let code = errorObj["code"]
            let composed = code != nil ? "\(msg) (\(code!))" : msg
            lastServerError = composed
            yield(.error(composed))
            yield(.connectionStateChanged(.failed(composed)))
            cleanupConnection()
            return
        }

        // setupComplete — session is ready
        if json["setupComplete"] != nil {
            // Atomically claim the success path. If the timeout task already won
            // (e.g. setupComplete arrived just past the 15s mark while the timeout
            // was emitting .failed), drop this event so we don't follow .failed
            // with a misleading .connected.
            stateLock.lock()
            let alreadyResolved = _didReachSetupComplete
            if !alreadyResolved {
                _didReachSetupComplete = true
            }
            stateLock.unlock()
            guard !alreadyResolved else { return }
            setupTimeoutTask?.cancel()
            setupTimeoutTask = nil
            yield(.connectionStateChanged(.connected))
            return
        }

        // serverContent — model turn with audio/text + transcriptions
        if let serverContent = json["serverContent"] as? [String: Any] {
            handleServerContent(serverContent)
            return
        }

        // toolCall — model wants to invoke a function
        if let toolCall = json["toolCall"] as? [String: Any],
           let functionCalls = toolCall["functionCalls"] as? [[String: Any]] {
            for call in functionCalls {
                guard let name = call["name"] as? String,
                      let callId = call["id"] as? String else { continue }
                let args: String
                if let argsDict = call["args"] as? [String: Any],
                   let argsData = try? JSONSerialization.data(withJSONObject: argsDict),
                   let argsString = String(data: argsData, encoding: .utf8) {
                    args = argsString
                } else {
                    args = "{}"
                }
                yield(.toolCallReceived(id: callId, name: name, arguments: args))
            }
            return
        }

        // goAway — server is shutting down. Perform full cleanup (close WebSocket, invalidate
        // URLSession, nil references) before emitting disconnected. Without this, the dead socket
        // lingers and send methods don't fail-fast. Consumers (VoiceChatViewModel) are responsible
        // for reconnecting if desired.
        if json["goAway"] != nil {
            cleanupConnection()
            yield(.connectionStateChanged(.disconnected))
            return
        }
    }

    private func handleServerContent(_ content: [String: Any]) {
        // Model turn — audio and text parts
        if let modelTurn = content["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {
            for part in parts {
                // Text part
                if let text = part["text"] as? String {
                    yield(.transcriptUpdate(role: .assistant, text: text, isFinal: false))
                }
                // Audio part (inlineData with base64 PCM)
                if let inlineData = part["inlineData"] as? [String: Any],
                   let base64 = inlineData["data"] as? String,
                   let audioData = Data(base64Encoded: base64) {
                    yield(.audioReceived(audioData))
                }
            }
        }

        // Input transcription — what the user said
        if let inputTranscription = content["inputTranscription"] as? [String: Any],
           let text = inputTranscription["text"] as? String, !text.isEmpty {
            yield(.transcriptUpdate(role: .user, text: text, isFinal: true))
        }

        // Output transcription — text version of what the model said
        if let outputTranscription = content["outputTranscription"] as? [String: Any],
           let text = outputTranscription["text"] as? String, !text.isEmpty {
            yield(.transcriptUpdate(role: .assistant, text: text, isFinal: true))
        }

        // Turn complete
        if let turnComplete = content["turnComplete"] as? Bool, turnComplete {
            yield(.turnComplete)
        }
    }

    // MARK: - Helpers

    private func sendJSON(_ dict: [String: Any]) async throws {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else {
            throw VoiceProviderError.encodingFailed
        }
        guard let task = webSocketTask else {
            throw VoiceProviderError.notConnected
        }
        try await task.send(.string(string))
    }

    private func yield(_ event: VoiceSessionEvent) {
        eventContinuation?.yield(event)
    }
}

// MARK: - Errors

enum VoiceProviderError: Error, LocalizedError {
    case invalidURL
    case encodingFailed
    case notConnected

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid WebSocket URL"
        case .encodingFailed: return "Failed to encode message"
        case .notConnected: return "Not connected to voice provider"
        }
    }
}
