@preconcurrency import AVFoundation
import Foundation
import Observation
import SwiftData

// MARK: - VoiceState

/// Lifecycle of a voice session. Strict state machine — every transition is
/// logged so misbehavior shows up in `app.log` even when the status window
/// is closed. Strings are stable identifiers; do not localize.
enum VoiceState: Equatable, Sendable {
    case idle
    case wakeListening
    case triggered
    case recording
    case thinking
    case speaking
    case toolRunning(String)
    case interrupted
    case error(String)
    case sleeping

    var label: String {
        switch self {
        case .idle: return "idle"
        case .wakeListening: return "wakeListening"
        case .triggered: return "triggered"
        case .recording: return "recording"
        case .thinking: return "thinking"
        case .speaking: return "speaking"
        case .toolRunning(let name): return "toolRunning(\(name))"
        case .interrupted: return "interrupted"
        case .error(let msg): return "error(\(msg))"
        case .sleeping: return "sleeping"
        }
    }
}

// MARK: - Trigger source

enum VoiceTrigger: String, Sendable {
    case hotkey
    case wake
    case manual
}

// MARK: - VoiceSessionCoordinator

/// Owns the live voice loop end-to-end. Replaces the inline state machine
/// that used to live in `MacVoiceChatPanel`'s view model so:
///   • the same coordinator runs whether the panel UI is open or not
///     (status window can drive it; hotkey can drive it)
///   • the audio input is fanned out via `AudioInputBroker` so wake-word
///     detection and Live both get frames without crashing AVAudioEngine
///   • disconnect persists a real `aiConversation` row server-side, which
///     in turn writes the transcript to Mem0 (see saveConversation hook in
///     apps/server/src/trpc/routes/ai/conversations.ts)
@MainActor
@Observable
final class VoiceSessionCoordinator {

    // MARK: - Published state

    private(set) var state: VoiceState = .idle
    private(set) var userTranscript: String = ""
    private(set) var assistantTranscript: String = ""
    private(set) var lastToolCall: String?
    private(set) var lastError: String?

    /// Finalized turns shown in transcript views, persisted on disconnect.
    private(set) var finalizedTurns: [VoiceTurn] = []

    /// Active trigger that opened this session — used so we know whether to
    /// return to `wakeListening` or `idle` on disconnect.
    private(set) var activeTrigger: VoiceTrigger?

    // MARK: - Dependencies (injected)

    private let tokenService: VoiceTokenService
    private let systemPromptClient: VoiceSystemPromptClient
    private let chatService: MacAIChatService
    private let apiClient: TodosAPIClient
    private let inputBroker: AudioInputBroker
    private let provider: VoiceProvider
    private let audioPlayer: AudioPlayerManager?
    private let hotkey: HotkeyService
    private let wakeService: WakeWordService

    /// SwiftData context — set lazily by the panel/window when one is available.
    /// Tool execution requires it; if absent we fall back to a friendly error.
    var modelContext: ModelContext?

    // MARK: - Internal state

    private var brokerToken: UUID?
    private var eventConsumerTask: Task<Void, Never>?
    private var conversationID: UUID?
    private var sessionStartedAt: Date?
    /// Reentrancy guard for `disconnect(reason:)` — multiple paths (explicit
    /// stop, error, provider goAway, panel dismissal) can all call disconnect
    /// nearly simultaneously. Without this they race on state teardown.
    private var isDisconnecting = false

    // MARK: - Audio send queue (serialized backpressure)

    /// Queue of PCM chunks waiting to be sent. A single long-running drain
    /// task ships them serially via `provider.sendAudioPCM` so we don't spawn
    /// an unbounded Task per buffer (the broker can fire ~10× per second).
    private var audioSendContinuation: AsyncStream<Data>.Continuation?
    private var audioSendDrainTask: Task<Void, Never>?
    /// Soft cap; oldest chunks are dropped past this to avoid unbounded growth
    /// if the provider stalls. Tracked with a simple counter — AsyncStream
    /// has no built-in size.
    private var audioSendQueueDepth = 0
    private static let audioSendMaxQueueDepth = 20

    // MARK: - Init

    init(
        tokenService: VoiceTokenService,
        systemPromptClient: VoiceSystemPromptClient,
        chatService: MacAIChatService,
        apiClient: TodosAPIClient,
        inputBroker: AudioInputBroker,
        hotkey: HotkeyService,
        wakeService: WakeWordService
    ) {
        self.tokenService = tokenService
        self.systemPromptClient = systemPromptClient
        self.chatService = chatService
        self.apiClient = apiClient
        self.inputBroker = inputBroker
        self.hotkey = hotkey
        self.wakeService = wakeService
        self.provider = GeminiLiveProvider()
        self.audioPlayer = AudioPlayerManager(sampleRate: 24000)

        wireTriggerCallbacks()
    }

    // MARK: - Public API

    /// Boot the trigger system. Always registers the hotkey; only attempts the
    /// wake word if the user has opted in via Settings.
    func start(enableWakeWord: Bool) {
        hotkey.register()
        if enableWakeWord {
            Task { [wakeService] in
                let started = await wakeService.start()
                if started {
                    self.transition(to: .wakeListening, reason: "wake-word started")
                }
            }
        }
        if state == .idle {
            // No wake — stay idle until the hotkey fires.
            transition(to: .idle, reason: "trigger system ready")
        }
    }

    /// Stop everything. Used on sign-out and app termination.
    func stop() async {
        await disconnect(reason: "explicit stop")
        wakeService.stop()
        hotkey.unregister()
    }

    /// Manually open a voice session (e.g. from the chat panel button).
    /// Equivalent to the user holding the hotkey down.
    func triggerManual() {
        Task { await beginSession(trigger: .manual) }
    }

    /// Send a typed text message mid-session. Lets the user interject without
    /// speaking — e.g. when correcting a misheard name.
    func sendText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard activeTrigger != nil else { return }
        Task {
            try? await provider.sendText(trimmed)
            if !userTranscript.isEmpty { userTranscript += " " }
            userTranscript += trimmed
        }
    }

    // MARK: - Trigger wiring

    private func wireTriggerCallbacks() {
        hotkey.onPress = { [weak self] in
            guard let self else { return }
            // Push-to-talk: hotkey-down opens the session if not open. If we
            // already have a hotkey-owned session but released the mic on the
            // previous release, re-attach the broker consumer for this new
            // turn so the user can speak again without tearing the WS down.
            if self.activeTrigger == nil {
                Task { await self.beginSession(trigger: .hotkey) }
            } else if self.activeTrigger == .hotkey && self.brokerToken == nil {
                Task { try? await self.attachAudioInput() }
            }
        }
        hotkey.onRelease = { [weak self] in
            guard let self else { return }
            // Hotkey-up (push-to-talk release): stop streaming mic frames so
            // we don't keep feeding silence into Gemini, then tell the model
            // the user's turn is over so it actually responds. We keep
            // `activeTrigger == .hotkey` set until the assistant finishes
            // speaking (cleared on `.turnComplete` in `handleEvent`) so a
            // second press during playback doesn't open a duplicate session.
            if self.activeTrigger == .hotkey {
                AppLogger.shared.log("[Voice] hotkey released — ending user turn")
                let token = self.brokerToken
                self.brokerToken = nil
                let providerRef = self.provider
                Task { [weak self] in
                    if let token, let broker = self?.inputBroker {
                        broker.removeConsumer(token)
                    }
                    // Best-effort end-of-turn nudge; harmless if the provider
                    // ignores it. Errors are swallowed because the WS may
                    // already be tearing down on a fast release.
                    try? await providerRef.sendActivityEnd()
                }
            }
        }

        wakeService.onDetected = { [weak self] in
            guard let self else { return }
            if self.activeTrigger == nil {
                Task { await self.beginSession(trigger: .wake) }
            }
        }
    }

    // MARK: - Session lifecycle

    private func beginSession(trigger: VoiceTrigger) async {
        guard activeTrigger == nil else { return }
        activeTrigger = trigger
        sessionStartedAt = Date()
        conversationID = UUID()
        finalizedTurns = []
        userTranscript = ""
        assistantTranscript = ""
        lastError = nil
        lastToolCall = nil

        transition(to: .triggered, reason: "trigger=\(trigger.rawValue)")

        // Mic permission gate — without this AVAudioEngine returns silence.
        let micGranted = await Self.requestMicrophoneAccess()
        guard micGranted else {
            failSession("Microphone access denied — enable Todus in System Settings → Privacy & Security → Microphone.")
            return
        }

        do {
            let prompt = await systemPromptClient.fetch()

            let (wsURL, authToken) = try await tokenService.getEndpoint()
            let config = VoiceSessionConfig.geminiDefault(
                systemInstruction: prompt.systemInstruction,
                tools: VoiceToolRegistry.declarations
            )

            try await provider.connect(endpoint: wsURL, authToken: authToken, config: config)
            startEventConsumer()

            // Attach to the shared input broker. This installs the AVAudioEngine
            // tap on first attach; subsequent attachments (wake word) reuse it.
            try await attachAudioInput()

            transition(to: .recording, reason: "audio input attached")
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            failSession(msg)
        }
    }

    private func attachAudioInput() async throws {
        // Spin up a serialized send queue. Previously every captured PCM
        // buffer spawned a fresh `Task { ... sendAudioPCM }`, which created
        // unbounded concurrency (~10 tasks/sec) and interleaved sends could
        // arrive out of order. Now a single drain task ships chunks
        // sequentially with backpressure.
        startAudioSendQueue()

        let token = try await inputBroker.addConsumer { [weak self] data in
            // NB: this closure runs on the audio thread. Don't capture the
            // continuation here — push-to-talk release/re-press cycles
            // `audioSendContinuation` via stop/startAudioSendQueue, so a
            // captured reference can point at a finished continuation and
            // silently drop audio. Always resolve through `self` on the main
            // actor to get the CURRENT continuation.
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let cont = self.audioSendContinuation else { return }
                // Backpressure: if the queue is already deep, drop this chunk
                // and log. AsyncStream doesn't expose direct removal, so we
                // approximate by tracking a counter on `self`.
                if self.audioSendQueueDepth >= Self.audioSendMaxQueueDepth {
                    AppLogger.shared.log("[Voice] audio send queue saturated (\(self.audioSendQueueDepth)); dropping chunk")
                    return
                }
                self.audioSendQueueDepth += 1
                cont.yield(data)
            }
        }
        brokerToken = token
    }

    /// Spin up the serial audio drain task. Idempotent — if a task is already
    /// running we tear it down first so a re-attach (e.g. after hotkey release
    /// then re-press) gets a fresh stream.
    private func startAudioSendQueue() {
        stopAudioSendQueue()
        var cont: AsyncStream<Data>.Continuation?
        let stream = AsyncStream<Data> { c in cont = c }
        audioSendContinuation = cont
        let providerRef = provider
        audioSendDrainTask = Task { [weak self] in
            for await chunk in stream {
                if Task.isCancelled { break }
                try? await providerRef.sendAudioPCM(chunk)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.audioSendQueueDepth = max(0, self.audioSendQueueDepth - 1)
                }
            }
        }
    }

    private func stopAudioSendQueue() {
        audioSendContinuation?.finish()
        audioSendContinuation = nil
        audioSendDrainTask?.cancel()
        audioSendDrainTask = nil
        audioSendQueueDepth = 0
    }

    /// Disconnect cleanly: stop audio, persist the transcript, return to the
    /// resting state (wakeListening or idle depending on whether wake is on).
    func disconnect(reason: String) async {
        guard activeTrigger != nil else { return }
        // Reentrancy guard: multiple paths (explicit stop, provider goAway,
        // error, panel dismissal) can call this concurrently. Without the
        // guard they double-tear-down state and the next session opens in a
        // half-disposed condition.
        guard !isDisconnecting else { return }
        isDisconnecting = true
        defer { isDisconnecting = false }

        if let brokerToken {
            inputBroker.removeConsumer(brokerToken)
            self.brokerToken = nil
        }
        // Drain the audio send queue so any in-flight chunks are dropped and
        // the background task exits cleanly before the provider disconnects.
        stopAudioSendQueue()
        audioPlayer?.stop()
        eventConsumerTask?.cancel()
        eventConsumerTask = nil
        await provider.disconnect()

        finalizeCurrentTurn()
        await persistTranscriptIfNeeded()
        finalizedTurns = []

        let wasTrigger = activeTrigger
        activeTrigger = nil
        conversationID = nil
        sessionStartedAt = nil

        AppLogger.shared.log("[Voice] disconnected (\(reason))")

        // Resting state depends on whether wake is active.
        if wakeService.isListening {
            transition(to: .wakeListening, reason: "session ended; wake active")
        } else {
            transition(to: .idle, reason: "session ended; hotkey only")
        }
        _ = wasTrigger
    }

    // MARK: - Event consumer

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
            switch state {
            case .connected:
                transition(to: .recording, reason: "WS connected")
            case .failed(let msg):
                failSession(msg)
            case .reconnecting, .connecting:
                break
            case .disconnected:
                // Only call disconnect if a session is actually active AND we're
                // not already mid-teardown. Without these guards a goAway frame
                // mid-disconnect re-enters and races on state cleanup.
                if activeTrigger != nil && !isDisconnecting {
                    Task { await disconnect(reason: "provider disconnected") }
                }
            }

        case .audioReceived(let data):
            audioPlayer?.enqueue(data)
            if state != .speaking { transition(to: .speaking, reason: "audio chunk") }

        case .transcriptUpdate(let role, let text, let isFinal):
            // Defensive accumulator: providers send deltas (per current
            // GeminiLiveProvider contract: isFinal=false per chunk) and we
            // append; but if a provider ever sends a cumulative snapshot we
            // detect and replace, and if it echoes an existing prefix we
            // skip. Prevents duplication if upstream semantics change.
            switch role {
            case .user:
                if isFinal {
                    userTranscript = text
                } else if text.hasPrefix(userTranscript) && text.count > userTranscript.count {
                    userTranscript = text
                } else if userTranscript.hasPrefix(text) {
                    // echoed prior text only — skip
                } else {
                    userTranscript += text
                }
            case .assistant:
                if isFinal {
                    assistantTranscript = text
                } else if text.hasPrefix(assistantTranscript) && text.count > assistantTranscript.count {
                    assistantTranscript = text
                } else if assistantTranscript.hasPrefix(text) {
                    // echoed prior text only — skip
                } else {
                    assistantTranscript += text
                }
            }

        case .toolCallReceived(let id, let name, let arguments):
            transition(to: .toolRunning(name), reason: "tool call")
            lastToolCall = name
            Task { [weak self] in
                guard let self else { return }
                let result = await self.executeTool(name: name, arguments: arguments)
                try? await self.provider.sendToolResponse(id: id, name: name, result: result)
                self.transition(to: .recording, reason: "tool '\(name)' done")
            }

        case .turnComplete:
            finalizeCurrentTurn()
            transition(to: .recording, reason: "turn complete")

        case .error(let message):
            failSession(message)
        }
    }

    // MARK: - Tool execution

    private func executeTool(name: String, arguments: String) async -> String {
        guard let modelContext else {
            return "{\"success\":false,\"message\":\"Voice session has no SwiftData context — open the chat panel first.\"}"
        }
        let executor = MacVoiceToolExecutor(chatService: chatService, modelContext: modelContext)
        let result = await VoiceToolRegistry.execute(
            name: name,
            argumentsJSON: arguments,
            executor: executor
        )
        // If the tool wrote anything that affects memory (e.g. a future
        // `remember` tool), a manual invalidation here would force the next
        // session to re-fetch the system prompt.
        return result
    }

    // MARK: - Transcript handling

    private func finalizeCurrentTurn() {
        let user = userTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let assistant = assistantTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !user.isEmpty || !assistant.isEmpty {
            finalizedTurns.append(VoiceTurn(id: UUID(), user: user, assistant: assistant))
        }
        userTranscript = ""
        assistantTranscript = ""
    }

    private func persistTranscriptIfNeeded() async {
        guard let conversationID, !finalizedTurns.isEmpty else { return }

        // Build a flat messages array — one user, one assistant, alternating.
        var messages: [SavedVoiceMessage] = []
        for turn in finalizedTurns {
            if !turn.user.isEmpty {
                messages.append(SavedVoiceMessage(role: "user", content: turn.user))
            }
            if !turn.assistant.isEmpty {
                messages.append(SavedVoiceMessage(role: "assistant", content: turn.assistant))
            }
        }
        guard !messages.isEmpty else { return }

        // Mirror the chat panel: also append to the shared chat history so
        // voice and text live in the same scrollback.
        for turn in finalizedTurns {
            chatService.appendVoiceExchange(userText: turn.user, assistantText: turn.assistant)
        }

        // Title — truncated first user utterance keeps the conversations list
        // readable. Fall back to "Voice session".
        let firstUser = finalizedTurns.first(where: { !$0.user.isEmpty })?.user ?? ""
        let title: String = {
            if firstUser.isEmpty { return "Voice session" }
            let trimmed = firstUser.prefix(60)
            return trimmed.count == firstUser.count ? String(trimmed) : trimmed + "…"
        }()

        let createdAt = sessionStartedAt ?? Date()
        let input = SaveVoiceConversationInput(
            id: conversationID.uuidString,
            title: title,
            messages: messages,
            folderId: nil,
            createdAt: ISO8601DateFormatter().string(from: createdAt)
        )

        do {
            let _: SyncSuccessLite = try await apiClient.trpcMutation(
                "ai.saveConversation",
                input: input
            )
            // Force the next session to re-fetch the system prompt so any
            // memories Mem0 just ingested show up immediately.
            systemPromptClient.invalidate()
            AppLogger.shared.log("[Voice] persisted transcript (\(messages.count) messages)")
        } catch {
            AppLogger.shared.log("[Voice] saveConversation failed: \(error.localizedDescription)")
        }
    }

    // MARK: - State transitions

    private func transition(to newState: VoiceState, reason: String) {
        if newState == state { return }
        AppLogger.shared.log("[Voice] \(state.label) → \(newState.label) (\(reason))")
        state = newState
    }

    private func failSession(_ message: String) {
        lastError = message
        AppLogger.shared.log("[Voice] error: \(message)")
        transition(to: .error(message), reason: "failure")
        Task { await disconnect(reason: "error") }
    }

    // MARK: - Mic permission

    private static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        @unknown default: return false
        }
    }
}

// MARK: - Voice transcript types

struct VoiceTurn: Identifiable, Sendable {
    let id: UUID
    let user: String
    let assistant: String
}

private struct SavedVoiceMessage: Encodable {
    let role: String
    let content: String
}

private struct SaveVoiceConversationInput: Encodable {
    let id: String
    let title: String
    let messages: [SavedVoiceMessage]
    let folderId: String?
    let createdAt: String
}

private struct SyncSuccessLite: Decodable {
    let success: Bool
}
