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
    /// Buffer accumulating PCM samples between timer fires
    private var pcmBuffer = Data()
    private let pcmBufferLock = NSLock()
    /// Thread-safe copy of isMicMuted for audio processing threads (tap + timer).
    /// Audio threads read this under micMutedLock; toggleMute() syncs it from isMicMuted.
    private var _micMutedAtomic = false
    private let micMutedLock = NSLock()

    // MARK: - Tasks

    private var eventConsumerTask: Task<Void, Never>?

    // MARK: - Context (injected before connect)

    /// All tasks from SwiftData — needed for system prompt and tool calls
    var allTasks: [TaskRecord] = []
    /// ModelContext for tool call execution
    var modelContext: ModelContext?

    // MARK: - Init

    init(tokenService: VoiceTokenService, chatService: AIChatService) {
        self.tokenService = tokenService
        self.chatService = chatService
        self.provider = GeminiLiveProvider()
        self.audioPlayer = AudioPlayerManager(sampleRate: 24000)
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

        connectionState = .connecting

        do {
            // 1. Get backend WebSocket proxy URL + auth token (API key stays server-side)
            let (wsURL, authToken) = try tokenService.getEndpoint()

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

            // 5. Start microphone capture — if this fails internally (sets state to .failed),
            //    clean up the provider connection so we don't leak a WebSocket
            startAudioCapture()
            if case .failed = connectionState {
                eventConsumerTask?.cancel()
                eventConsumerTask = nil
                await provider.disconnect()
            }

        } catch {
            // Clean up provider if it was already connected before the error
            await provider.disconnect()
            // Provide user-friendly error messages for common failure modes
            let message: String
            if let voiceError = error as? VoiceEndpointError {
                message = voiceError.errorDescription ?? error.localizedDescription
            } else if error.localizedDescription.lowercased().contains("bad") ||
                      error.localizedDescription.lowercased().contains("websocket") {
                message = "Voice service unavailable — check your connection and try again"
            } else {
                message = error.localizedDescription
            }
            connectionState = .failed(message)
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
            defer {
                activeToolCallCount -= 1
                if activeToolCallCount <= 0 {
                    activeToolCallCount = 0
                    toolCallStatus = nil
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
            }
        }
    }

    // MARK: - Audio Capture

    private func startAudioCapture() {
        do {
            let session = AVAudioSession.sharedInstance()
            // .playAndRecord allows simultaneous capture + playback (unlike .record used in VoiceInputButton)
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            connectionState = .failed("Audio session setup failed: \(error.localizedDescription)")
            return
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Target format: PCM16 mono @ 16kHz (Gemini requirement)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ) else {
            connectionState = .failed("Failed to create target audio format")
            return
        }

        // Install converter if sample rate / format differs
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            connectionState = .failed("Cannot create audio format converter")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            // Read thread-safe flag instead of main-actor-isolated isMicMuted (avoids data race)
            self.micMutedLock.lock()
            let muted = self._micMutedAtomic
            self.micMutedLock.unlock()
            guard !muted else { return }

            // Convert to PCM16 16kHz
            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * 16000.0 / inputFormat.sampleRate
            )
            guard frameCount > 0,
                  let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount)
            else { return }

            var error: NSError?
            // The input block must supply data exactly once; returning .noDataNow on subsequent
            // calls prevents the converter from re-reading the same buffer in a loop.
            // Uses a reference-type flag so the @Sendable closure captures a let, not a var.
            // @unchecked Sendable is safe: convert(to:error:inputBlock:) calls the block synchronously.
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
                // Extract raw PCM bytes and append to buffer
                let byteCount = Int(convertedBuffer.frameLength) * MemoryLayout<Int16>.size
                if let channelData = convertedBuffer.int16ChannelData?[0] {
                    let data = Data(bytes: channelData, count: byteCount)
                    self.pcmBufferLock.lock()
                    self.pcmBuffer.append(data)
                    self.pcmBufferLock.unlock()
                }
            }
        }

        do {
            engine.prepare()
            try engine.start()
            captureEngine = engine
        } catch {
            connectionState = .failed("Audio engine start failed: \(error.localizedDescription)")
            return
        }

        // Send buffered audio every 100ms
        startAudioSendTimer()
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

        captureEngine?.stop()
        captureEngine?.inputNode.removeTap(onBus: 0)
        captureEngine = nil

        pcmBufferLock.lock()
        pcmBuffer = Data()
        pcmBufferLock.unlock()

        // Deactivate audio session so other apps can use audio
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - Private Helpers

/// Mutable Boolean reference: lets @Sendable closures capture a mutable flag via a let constant.
/// Marked @unchecked Sendable because the usage context is always single-threaded (synchronous callback).
private final class _MutableBoolRef: @unchecked Sendable {
    var value: Bool = false
}
