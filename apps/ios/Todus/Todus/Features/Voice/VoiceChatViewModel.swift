@preconcurrency import AVFoundation
import Foundation
import Observation
import SwiftData

// MARK: - VoiceChatViewModel

/// Drives the VoiceChatModalView. Manages the voice provider, audio capture/playback,
/// transcript state, and tool call routing.
///
/// Owns:
/// - A `VoiceProvider` (currently `GeminiLiveProvider`)
/// - An `AudioPlayerManager` for playing assistant audio
/// - An `AVAudioEngine` for capturing microphone input
///
/// Partial transcripts live here only; finalized exchanges are written back
/// to `AIChatService.messages` when the session ends.
@MainActor
@Observable
final class VoiceChatViewModel {

    // MARK: - Published State

    var connectionState: VoiceConnectionState = .disconnected
    var userTranscript: String = ""
    var assistantTranscript: String = ""
    var isMicMuted: Bool = false
    var isAssistantSpeaking: Bool = false
    var toolCallStatus: String? = nil

    /// Finalized conversation turns (complete user + assistant exchanges).
    /// Displayed in the transcript scroll area and written to AIChatService on disconnect.
    private(set) var finalizedTurns: [(id: UUID, user: String, assistant: String)] = []

    // MARK: - Dependencies

    private let tokenService: VoiceTokenService
    private let chatService: AIChatService
    private let provider: VoiceProvider
    private let audioPlayer: AudioPlayerManager?

    // MARK: - Audio Capture

    private var captureEngine: AVAudioEngine?
    /// Timer-based audio chunk sending (100ms intervals)
    private var audioSendTimer: DispatchSourceTimer?
    /// Buffer accumulating PCM samples between timer fires. Lock-guarded audio
    /// plumbing, not UI state — kept out of @Observable tracking.
    @ObservationIgnored nonisolated(unsafe) private var pcmBuffer = Data()
    private let pcmBufferLock = NSLock()
    /// Thread-safe copy of isMicMuted for audio processing threads (tap + timer).
    /// Audio threads read this under micMutedLock; toggleMute() syncs it from isMicMuted.
    @ObservationIgnored nonisolated(unsafe) private var _micMutedAtomic = false
    private let micMutedLock = NSLock()

    // MARK: - Tasks

    private var eventConsumerTask: Task<Void, Never>?

    // MARK: - Context (injected before connect)

    /// All tasks from SwiftData — needed for system prompt and tool calls
    var allTasks: [TaskRecord] = []
    /// ModelContext for tool call execution
    var modelContext: ModelContext?

    // MARK: - Init

    /// Optional shared mic lock — when provided, this view-model cooperates
    /// with `VoiceSessionCoordinator` so a Siri Shortcut and the in-app modal
    /// can't both start AVAudioEngine at the same time (same class of bug as
    /// H17 double-attach crash). nil keeps existing behavior for callers that
    /// don't pass it.
    private let micLock: VoiceMicLock?
    private static let micOwner = "modal"

    init(
        tokenService: VoiceTokenService,
        chatService: AIChatService,
        micLock: VoiceMicLock? = nil
    ) {
        self.tokenService = tokenService
        self.chatService = chatService
        self.provider = GeminiLiveProvider()
        self.audioPlayer = AudioPlayerManager(sampleRate: 24000)
        self.micLock = micLock
    }

    // MARK: - Connect

    /// Whether the current state allows starting a new connection.
    private var canConnect: Bool {
        switch connectionState {
        case .disconnected, .failed: return true
        default: return false
        }
    }

    func connect() async {
        guard canConnect else { return }

        if let micLock, !micLock.acquire(owner: Self.micOwner) {
            connectionState = .failed("Voice is already active in another window — close it before opening this one.")
            return
        }

        connectionState = .connecting

        do {
            // 1. Get backend WebSocket proxy URL + auth token (API key stays server-side)
            let (wsURL, authToken) = try await tokenService.getEndpoint()

            // 2. Build system prompt using same pipeline as text chat
            let systemPrompt = await chatService.buildSystemPromptForVoice(allTasks: allTasks)

            // 3. Configure and connect to backend proxy (which relays to Gemini)
            let tools = chatService.voiceToolDeclarations()
            let config = VoiceSessionConfig.geminiDefault(
                systemInstruction: systemPrompt,
                tools: tools
            )
            try await provider.connect(endpoint: wsURL, authToken: authToken, config: config)

            // 4. Start consuming events from provider
            startEventConsumer()

            // 5. Start microphone capture — must be `await` because audio setup (especially
            //    AVAudioSession.setActive on iOS) regularly blocks for 1–5s and was causing
            //    main-thread stalls long enough for iOS's watchdog to terminate the app.
            //    The implementation runs the heavy work on a background queue.
            await startAudioCapture()
            // A trailing provider event delivered between eventConsumerTask
            // cancellation and provider.disconnect() returning can no longer overwrite
            // .failed — handleEvent ignores all events once connectionState is .failed.
            if case .failed = connectionState {
                eventConsumerTask?.cancel()
                eventConsumerTask = nil
                await provider.disconnect()
                micLock?.release(owner: Self.micOwner)
            }

        } catch {
            // Clean up provider if it was already connected before the error
            await provider.disconnect()
            let message: String
            if let voiceError = error as? VoiceEndpointError {
                message = voiceError.errorDescription ?? error.localizedDescription
            } else {
                // Show the raw error so Gemini/server errors are visible.
                // "bad server response" means the server returned a non-101 HTTP status
                // instead of upgrading to WebSocket — check server logs for the cause.
                message = error.localizedDescription
            }
            connectionState = .failed(message)
            micLock?.release(owner: Self.micOwner)
        }
    }

    // MARK: - Disconnect

    func disconnect() async {
        // Guard: prevent double-disconnect (button calls disconnect+dismiss, then onDisappear fires disconnect again)
        guard connectionState != .disconnected else { return }

        // Stop audio capture
        stopAudioCapture()

        // Stop playback
        audioPlayer?.stop()

        // Cancel event consumer
        eventConsumerTask?.cancel()
        eventConsumerTask = nil

        // Disconnect provider
        await provider.disconnect()

        // Finalize any in-progress turn
        finalizeCurrentTurn()

        // Write all finalized exchanges to main chat history
        for turn in finalizedTurns {
            chatService.appendVoiceExchange(
                userText: turn.user,
                assistantText: turn.assistant
            )
        }
        // Clear after writing to prevent duplicates if disconnect is called again
        finalizedTurns = []

        connectionState = .disconnected
        micLock?.release(owner: Self.micOwner)
    }

    // MARK: - Mute Toggle

    func toggleMute() {
        isMicMuted.toggle()
        // Sync thread-safe copy for audio processing threads (tap + timer run off-main-actor)
        micMutedLock.lock()
        _micMutedAtomic = isMicMuted
        micMutedLock.unlock()
    }

    // MARK: - Send Text (optional text input during voice session)

    func sendText(_ text: String) {
        guard connectionState == .connected,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            try? await provider.sendText(text)
            // Record as part of current user transcript
            if !userTranscript.isEmpty { userTranscript += " " }
            userTranscript += text
        }
    }

    // MARK: - Event Consumer

    private func startEventConsumer() {
        eventConsumerTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.provider.events {
                guard !Task.isCancelled else { break }
                self.handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: VoiceSessionEvent) {
        // Once the session has terminally failed, ignore trailing provider events
        // (delivered between consumer cancellation and disconnect() returning) so a
        // late event can't overwrite .failed and resurrect a half-torn-down session.
        if case .failed = connectionState { return }
        switch event {
        case .connectionStateChanged(let state):
            connectionState = state

        case .audioReceived(let data):
            audioPlayer?.enqueue(data)
            isAssistantSpeaking = true

        case .transcriptUpdate(let role, let text, let isFinal):
            switch role {
            case .user:
                if isFinal {
                    userTranscript = text
                } else {
                    userTranscript += text
                }
            case .assistant:
                if isFinal {
                    assistantTranscript = text
                } else {
                    assistantTranscript += text
                }
            }

        case .toolCallReceived(let id, let name, let arguments):
            handleToolCall(id: id, name: name, arguments: arguments)

        case .turnComplete:
            isAssistantSpeaking = false
            finalizeCurrentTurn()

        case .error(let message):
            connectionState = .failed(message)
        }
    }

    // MARK: - Turn Finalization

    /// Moves the current partial transcripts into the finalized turns array
    /// and clears the live transcript state for the next exchange.
    private func finalizeCurrentTurn() {
        let user = userTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let assistant = assistantTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

        if !user.isEmpty || !assistant.isEmpty {
            finalizedTurns.append((id: UUID(), user: user, assistant: assistant))
        }

        userTranscript = ""
        assistantTranscript = ""
    }

    // MARK: - Tool Call Handling

    /// Tracks in-flight tool calls to avoid status clobbering when multiple calls arrive concurrently.
    private var activeToolCallCount = 0

    private func handleToolCall(id: String, name: String, arguments: String) {
        // Show status in UI (track count so concurrent calls don't clear each other's status)
        activeToolCallCount += 1
        let displayName = name.replacingOccurrences(of: "_", with: " ")
        toolCallStatus = "Running \(displayName)..."

        Task {
            var showingFailure = false
            defer {
                activeToolCallCount -= 1
                if activeToolCallCount <= 0 {
                    activeToolCallCount = 0
                    // Don't clear a freshly set failure banner — the 4-second auto-clear handles it.
                    if !showingFailure {
                        toolCallStatus = nil
                    }
                }
            }

            guard let modelContext else {
                // No model context — can't execute tool calls
                do {
                    try await provider.sendToolResponse(
                        id: id, name: name,
                        result: "{\"error\": \"Tool execution unavailable\"}"
                    )
                } catch {
                    print("[VoiceChatVM] Failed to send tool error response for \(name): \(error)")
                }
                return
            }

            // Execute through existing AIChatService pipeline
            let result = await chatService.processVoiceToolCall(
                name: name,
                arguments: arguments,
                modelContext: modelContext
            )

            // Send result back to Gemini
            do {
                try await provider.sendToolResponse(id: id, name: name, result: result)
            } catch {
                print("[VoiceChatVM] Failed to send tool response for \(name)(\(id)): \(error)")
                // Surface the failure to the user briefly — otherwise tool errors
                // disappear silently and the assistant looks unresponsive.
                let failureMessage = "Tool failed: \(error.localizedDescription)"
                showingFailure = true
                await MainActor.run {
                    self.toolCallStatus = failureMessage
                }
                // Auto-clear after 4 seconds so the banner doesn't linger.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if self?.toolCallStatus == failureMessage {
                        self?.toolCallStatus = nil
                    }
                }
            }
        }
    }

    // MARK: - Audio Capture

    /// Result of off-main audio setup — has to be a single value type so we can hand
    /// it through CheckedContinuation without crossing actors with non-Sendable refs.
    private enum AudioCaptureSetup {
        case success(AVAudioEngine)
        case failed(String)
    }

    private func startAudioCapture() async {
        // Hop OFF the main actor for the entire setup chain. AVAudioSession.setActive
        // and AVAudioEngine.start() routinely block for seconds — long enough that
        // iOS's main-thread watchdog terminates the app (the user saw 5.8s stalls
        // followed by the app closing). Tap callback already runs on its own audio
        // thread; only the synchronous setup needed offloading.
        let result: AudioCaptureSetup = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else {
                    cont.resume(returning: .failed("Voice session was cancelled"))
                    return
                }

                // 1. Audio session — slowest step, especially with Bluetooth in range.
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(
                        .playAndRecord,
                        mode: .voiceChat,
                        options: [.defaultToSpeaker, .allowBluetoothHFP]
                    )
                    try session.setActive(true, options: .notifyOthersOnDeactivation)
                } catch {
                    cont.resume(returning: .failed(
                        "Audio session setup failed: \(error.localizedDescription)"
                    ))
                    return
                }

                // 2. Build the audio graph.
                let engine = AVAudioEngine()
                let inputNode = engine.inputNode
                let inputFormat = inputNode.outputFormat(forBus: 0)

                guard inputFormat.sampleRate > 0 else {
                    cont.resume(returning: .failed("No microphone input is available"))
                    return
                }

                guard let targetFormat = AVAudioFormat(
                    commonFormat: .pcmFormatInt16,
                    sampleRate: 16000,
                    channels: 1,
                    interleaved: true
                ) else {
                    cont.resume(returning: .failed("Failed to create target audio format"))
                    return
                }

                guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                    cont.resume(returning: .failed("Cannot create audio format converter"))
                    return
                }

                inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                    guard let self else { return }
                    self.micMutedLock.lock()
                    let muted = self._micMutedAtomic
                    self.micMutedLock.unlock()
                    guard !muted else { return }

                    let frameCount = AVAudioFrameCount(
                        Double(buffer.frameLength) * 16000.0 / inputFormat.sampleRate
                    )
                    guard frameCount > 0,
                          let convertedBuffer = AVAudioPCMBuffer(
                              pcmFormat: targetFormat,
                              frameCapacity: frameCount
                          )
                    else { return }

                    var error: NSError?
                    let suppliedInput = _MutableBoolRef()
                    converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                        if suppliedInput.value {
                            outStatus.pointee = .noDataNow
                            return nil
                        }
                        suppliedInput.value = true
                        outStatus.pointee = .haveData
                        return buffer
                    }

                    if error == nil, convertedBuffer.frameLength > 0 {
                        let byteCount = Int(convertedBuffer.frameLength) * MemoryLayout<Int16>.size
                        if let channelData = convertedBuffer.int16ChannelData?[0] {
                            let data = Data(bytes: channelData, count: byteCount)
                            self.pcmBufferLock.lock()
                            self.pcmBuffer.append(data)
                            self.pcmBufferLock.unlock()
                        }
                    }
                }

                // 3. Start the engine — also slow on cold start.
                do {
                    engine.prepare()
                    try engine.start()
                } catch {
                    inputNode.removeTap(onBus: 0)
                    cont.resume(returning: .failed(
                        "Audio engine start failed: \(error.localizedDescription)"
                    ))
                    return
                }

                cont.resume(returning: .success(engine))
            }
        }

        // Back on the main actor — only state-mutating work happens here.
        switch result {
        case .success(let engine):
            guard connectionState == .connecting || connectionState == .connected || connectionState == .reconnecting else {
                DispatchQueue.global(qos: .userInitiated).async {
                    engine.stop()
                    engine.inputNode.removeTap(onBus: 0)
                    try? AVAudioSession.sharedInstance().setActive(
                        false,
                        options: .notifyOthersOnDeactivation
                    )
                }
                return
            }
            captureEngine = engine
            startAudioSendTimer()
        case .failed(let message):
            connectionState = .failed(message)
        }
    }

    private func startAudioSendTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            // Check mute state from thread-safe copy (belt-and-suspenders: tap already skips when muted)
            self.micMutedLock.lock()
            let muted = self._micMutedAtomic
            self.micMutedLock.unlock()
            guard !muted else { return }

            self.pcmBufferLock.lock()
            let chunk = self.pcmBuffer
            self.pcmBuffer = Data()
            self.pcmBufferLock.unlock()

            guard !chunk.isEmpty else { return }
            Task {
                try? await self.provider.sendAudioPCM(chunk)
            }
        }
        timer.resume()
        audioSendTimer = timer
    }

    private func stopAudioCapture() {
        audioSendTimer?.cancel()
        audioSendTimer = nil

        let engineToStop = captureEngine
        captureEngine = nil

        pcmBufferLock.lock()
        pcmBuffer = Data()
        pcmBufferLock.unlock()

        // engine.stop(), removeTap, and setActive(false) can all block for hundreds of
        // ms — fire them off-main so dismissing the modal stays responsive.
        DispatchQueue.global(qos: .userInitiated).async {
            engineToStop?.stop()
            engineToStop?.inputNode.removeTap(onBus: 0)
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        }
    }
}

// MARK: - Private Helpers

/// Mutable Boolean reference: lets @Sendable closures capture a mutable flag via a let constant.
/// Marked @unchecked Sendable because the usage context is always single-threaded (synchronous callback).
private final class _MutableBoolRef: @unchecked Sendable {
    var value: Bool = false
}
