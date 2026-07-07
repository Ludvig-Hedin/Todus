@preconcurrency import AVFoundation
import Foundation
import Observation
import SwiftData

// MARK: - VoiceSessionStatus

/// Lifecycle of a voice session driven by `VoiceSessionCoordinator`.
/// Mirrors the macOS `VoiceState` machine but simplified for iOS (no hotkey
/// or wake-word path — the session is opened explicitly by UI or an
/// AppIntent / Siri Shortcut). Strings are stable identifiers; do not localize.
enum VoiceSessionStatus: Equatable, Sendable {
    case idle
    case connecting
    case listening
    case speaking
    case toolRunning(String)
    case error(String)

    var label: String {
        switch self {
        case .idle: return "idle"
        case .connecting: return "connecting"
        case .listening: return "listening"
        case .speaking: return "speaking"
        case .toolRunning(let name): return "toolRunning(\(name))"
        case .error(let msg): return "error(\(msg))"
        }
    }
}

// MARK: - VoiceSessionCoordinator

/// Owns an iOS voice session end-to-end. Mirrors `MacVoiceSessionCoordinator`
/// using iOS-native primitives:
///   • Token acquisition via `VoiceTokenService`
///   • Server-built system prompt via `VoiceSystemPromptClient`
///   • Tool dispatch via `VoiceToolRegistry` + `IOSVoiceToolExecutor`
///   • Audio capture via `VoiceAudioCapture`, playback via `AudioPlayerManager`
///   • Persists transcript on `stop()` via `ai.saveConversation` (same as macOS)
///
/// The existing `VoiceChatViewModel` continues to drive the modal sheet so the
/// in-app modal experience keeps working. This coordinator is a parallel,
/// modal-less driver used by Shortcut/AppIntent activation and Settings.
@MainActor
@Observable
final class VoiceSessionCoordinator {

    // MARK: - Published state

    private(set) var status: VoiceSessionStatus = .idle
    private(set) var userTranscript: String = ""
    private(set) var assistantTranscript: String = ""
    private(set) var lastToolCall: String?
    private(set) var lastError: String?

    /// Finalized turns shown in transcript views, persisted on stop.
    private(set) var finalizedTurns: [VoiceTurn] = []

    // MARK: - Dependencies

    private let tokenService: VoiceTokenService
    private let systemPromptClient: VoiceSystemPromptClient
    private let chatService: AIChatService
    private let apiClient: TodosAPIClient
    private let provider: VoiceProvider
    private let audioPlayer: AudioPlayerManager?
    private let capture: VoiceAudioCapture
    private let micLock: VoiceMicLock?
    private static let micOwner = "coordinator"

    /// SwiftData context — set lazily by the caller (e.g. SettingsView) when
    /// available so tool calls can mutate `TaskRecord`. Without it, the
    /// registry returns a friendly error string for write tools.
    var modelContext: ModelContext?

    // MARK: - Internal state

    private var eventConsumerTask: Task<Void, Never>?
    private var conversationID: UUID?
    private var sessionStartedAt: Date?
    private var isStopping = false

    // MARK: - Init

    init(
        tokenService: VoiceTokenService,
        systemPromptClient: VoiceSystemPromptClient,
        chatService: AIChatService,
        apiClient: TodosAPIClient,
        micLock: VoiceMicLock? = nil
    ) {
        self.tokenService = tokenService
        self.systemPromptClient = systemPromptClient
        self.chatService = chatService
        self.apiClient = apiClient
        self.provider = GeminiLiveProvider()
        self.audioPlayer = AudioPlayerManager(sampleRate: 24000)
        self.capture = VoiceAudioCapture()
        self.micLock = micLock
        wireCaptureCallback()
    }

    // MARK: - Public API

    /// Open a voice session. Idempotent — calling while a session is open or
    /// connecting is a no-op so duplicate Shortcut triggers don't double-open.
    func start() async {
        switch status {
        case .idle, .error:
            break
        default:
            return
        }

        if let micLock, !micLock.acquire(owner: Self.micOwner) {
            failSession("Voice is already active in another window — close it before starting a new session.")
            return
        }

        sessionStartedAt = Date()
        conversationID = UUID()
        finalizedTurns = []
        userTranscript = ""
        assistantTranscript = ""
        lastError = nil
        lastToolCall = nil

        transition(to: .connecting, reason: "start()")

        let micGranted = await Self.requestMicrophoneAccess()
        guard micGranted else {
            failSession("Microphone access denied — enable Todus in Settings → Privacy → Microphone.")
            return
        }

        do {
            let systemInstruction = await systemPromptClient.fetchSystemPrompt()
            let (wsURL, authToken) = try await tokenService.getEndpoint()
            let config = VoiceSessionConfig.geminiDefault(
                systemInstruction: systemInstruction,
                tools: VoiceToolRegistry.declarations
            )
            try await provider.connect(endpoint: wsURL, authToken: authToken, config: config)
            startEventConsumer()

            switch await capture.start() {
            case .success:
                break
            case .failed(let message):
                failSession(message)
                return
            }

            transition(to: .listening, reason: "audio attached")
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            failSession(msg)
        }
    }

    /// Stop everything: tear down audio capture/playback, persist the
    /// transcript via `ai.saveConversation`, return to `.idle`. Reentrancy
    /// guarded so duplicate stop() calls (UI dismiss + error path) are safe.
    func stop() async {
        guard !isStopping else { return }
        isStopping = true
        defer {
            isStopping = false
            micLock?.release(owner: Self.micOwner)
        }

        capture.stop()
        audioPlayer?.stop()
        eventConsumerTask?.cancel()
        eventConsumerTask = nil
        await provider.disconnect()

        finalizeCurrentTurn()
        await persistTranscriptIfNeeded()
        finalizedTurns = []
        conversationID = nil
        sessionStartedAt = nil

        transition(to: .idle, reason: "stop()")
    }

    /// Send a typed text mid-session — mirrors the macOS coordinator. Lets the
    /// user interject without speaking (e.g. correcting a misheard name).
    func sendText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch status {
        case .listening, .speaking, .toolRunning:
            break
        default:
            return
        }
        Task {
            try? await provider.sendText(trimmed)
            if !userTranscript.isEmpty { userTranscript += " " }
            userTranscript += trimmed
        }
    }

    // MARK: - Audio plumbing

    private func wireCaptureCallback() {
        let providerRef = provider
        capture.onChunk = { chunk in
            // onChunk is invoked off-main from a DispatchSource timer; fire
            // a fresh Task so the async provider call lives outside the timer.
            Task.detached {
                try? await providerRef.sendAudioPCM(chunk)
            }
        }
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
        case .connectionStateChanged(let connState):
            switch connState {
            case .connected:
                if status != .listening && status != .speaking {
                    transition(to: .listening, reason: "WS connected")
                }
            case .failed(let msg):
                failSession(msg)
            case .connecting, .reconnecting:
                break
            case .disconnected:
                if status != .idle && !isStopping {
                    Task { await stop() }
                }
            }

        case .audioReceived(let data):
            audioPlayer?.enqueue(data)
            if status != .speaking { transition(to: .speaking, reason: "audio chunk") }

        case .transcriptUpdate(let role, let text, let isFinal):
            switch role {
            case .user:
                if isFinal { userTranscript = text } else { userTranscript += text }
            case .assistant:
                if isFinal { assistantTranscript = text } else { assistantTranscript += text }
            }

        case .toolCallReceived(let id, let name, let arguments):
            transition(to: .toolRunning(name), reason: "tool call")
            lastToolCall = name
            Task { [weak self] in
                guard let self else { return }
                let result = await self.executeTool(name: name, arguments: arguments)
                // The user may have stopped the session while the tool ran —
                // transitioning back to .listening here resurrected a dead,
                // mic-released session as "active".
                guard !self.isStopping, self.status != .idle else { return }
                try? await self.provider.sendToolResponse(id: id, name: name, result: result)
                guard !self.isStopping, self.status != .idle else { return }
                self.transition(to: .listening, reason: "tool '\(name)' done")
            }

        case .turnComplete:
            finalizeCurrentTurn()
            transition(to: .listening, reason: "turn complete")

        case .error(let message):
            failSession(message)
        }
    }

    // MARK: - Tool execution

    private func executeTool(name: String, arguments: String) async -> String {
        guard let modelContext else {
            return "{\"success\":false,\"message\":\"Voice session has no SwiftData context — open the chat panel first.\"}"
        }
        let executor = IOSVoiceToolExecutor(chatService: chatService, modelContext: modelContext)
        return await VoiceToolRegistry.execute(
            name: name,
            argumentsJSON: arguments,
            executor: executor
        )
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

        // Also append to the shared chat history so voice and text live in
        // the same scrollback — matches the in-app modal behaviour.
        for turn in finalizedTurns {
            chatService.appendVoiceExchange(userText: turn.user, assistantText: turn.assistant)
        }

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
            systemPromptClient.invalidateCache()
        } catch {
            AppLogger.shared.log("[VoiceSessionCoordinator] saveConversation failed: \(error.localizedDescription)")
        }
    }

    // MARK: - State transitions

    private func transition(to newState: VoiceSessionStatus, reason: String) {
        if newState == status { return }
        AppLogger.shared.log("[VoiceSessionCoordinator] \(status.label) → \(newState.label) (\(reason))")
        status = newState
    }

    private func failSession(_ message: String) {
        lastError = message
        AppLogger.shared.log("[VoiceSessionCoordinator] error: \(message)")
        transition(to: .error(message), reason: "failure")
        Task { await stop() }
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
