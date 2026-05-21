@preconcurrency import AVFoundation
import Foundation
import Observation
import SwiftUI

// MARK: - MacVoiceChatViewModel

/// Drives a live voice session for the macOS app. Mirrors iOS's VoiceChatViewModel
/// but uses macOS audio APIs (no AVAudioSession — that's iOS-only).
///
/// Audio path:
/// - Input: AVAudioEngine.inputNode tap → AVAudioConverter to PCM16 16kHz mono
/// - Output: AudioPlayerManager (PCM16 24kHz mono) playing assistant audio chunks
@MainActor
@Observable
final class MacVoiceChatViewModel {

    // MARK: - Published state

    var connectionState: VoiceConnectionState = .disconnected
    var userTranscript: String = ""
    var assistantTranscript: String = ""
    var isMicMuted: Bool = false
    var isAssistantSpeaking: Bool = false

    /// Finalized turns (complete user + assistant exchanges) shown in the transcript.
    private(set) var finalizedTurns: [(id: UUID, user: String, assistant: String)] = []

    // MARK: - Dependencies

    private let tokenService: VoiceTokenService
    private let chatService: MacAIChatService
    private let provider: VoiceProvider
    private let audioPlayer: AudioPlayerManager?

    // MARK: - Audio capture

    private var captureEngine: AVAudioEngine?
    private var audioSendTimer: DispatchSourceTimer?
    nonisolated(unsafe) private var pcmBuffer = Data()
    let pcmBufferLock = NSLock()
    nonisolated(unsafe) private var _micMutedAtomic = false
    let micMutedLock = NSLock()

    // MARK: - Tasks

    private var eventConsumerTask: Task<Void, Never>?

    // MARK: - Init

    init(tokenService: VoiceTokenService, chatService: MacAIChatService) {
        self.tokenService = tokenService
        self.chatService = chatService
        self.provider = GeminiLiveProvider()
        self.audioPlayer = AudioPlayerManager(sampleRate: 24000)
    }

    // MARK: - Connect / disconnect

    private var canConnect: Bool {
        switch connectionState {
        case .disconnected, .failed: return true
        default: return false
        }
    }

    func connect() async {
        guard canConnect else { return }
        connectionState = .connecting

        // macOS Hardened Runtime requires explicit mic access — querying AVAudioEngine.inputNode
        // before this is granted produces -10877 / kAudioHardwareUnsupportedOperationError and the
        // engine starts but captures silence. Request first; bail with a clear reason if denied.
        let micGranted = await Self.requestMicrophoneAccess()
        guard micGranted else {
            connectionState = .failed("Microphone access denied — enable Todus in System Settings → Privacy & Security → Microphone.")
            return
        }

        do {
            let (wsURL, authToken) = try await tokenService.getEndpoint()

            let systemPrompt = Self.buildSystemPrompt(
                contextAboutYou: chatService.contextAboutYou,
                customInstructions: chatService.customInstructions
            )

            let config = VoiceSessionConfig.geminiDefault(
                systemInstruction: systemPrompt
            )
            try await provider.connect(endpoint: wsURL, authToken: authToken, config: config)

            startEventConsumer()
            // AVAudioEngine.start() can block for hundreds of ms; do not run it on the
            // main actor or the panel can lock up while connecting.
            await startAudioCapture()
            if case .failed = connectionState {
                eventConsumerTask?.cancel()
                eventConsumerTask = nil
                await provider.disconnect()
            }
        } catch {
            await provider.disconnect()
            let message: String
            if let voiceError = error as? VoiceEndpointError {
                message = voiceError.errorDescription ?? error.localizedDescription
            } else {
                message = error.localizedDescription
            }
            connectionState = .failed(message)
        }
    }

    func disconnect() async {
        guard connectionState != .disconnected else { return }

        stopAudioCapture()
        audioPlayer?.stop()

        eventConsumerTask?.cancel()
        eventConsumerTask = nil

        await provider.disconnect()

        finalizeCurrentTurn()
        for turn in finalizedTurns {
            chatService.appendVoiceExchange(userText: turn.user, assistantText: turn.assistant)
        }
        finalizedTurns = []

        connectionState = .disconnected
    }

    // MARK: - Mute

    func toggleMute() {
        isMicMuted.toggle()
        micMutedLock.lock()
        _micMutedAtomic = isMicMuted
        micMutedLock.unlock()
    }

    // MARK: - Send text mid-session

    func sendText(_ text: String) {
        guard connectionState == .connected,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            try? await provider.sendText(text)
            if !userTranscript.isEmpty { userTranscript += " " }
            userTranscript += text
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
        case .connectionStateChanged(let state):
            connectionState = state
        case .audioReceived(let data):
            audioPlayer?.enqueue(data)
            isAssistantSpeaking = true
        case .transcriptUpdate(let role, let text, let isFinal):
            switch role {
            case .user:
                if isFinal { userTranscript = text } else { userTranscript += text }
            case .assistant:
                if isFinal { assistantTranscript = text } else { assistantTranscript += text }
            }
        case .toolCallReceived(let id, let name, _):
            // Tool calls aren't wired to macOS yet — return a deterministic "unsupported"
            // result so Gemini doesn't hang waiting for a response.
            Task {
                try? await self.provider.sendToolResponse(
                    id: id, name: name,
                    result: "{\"success\":false,\"message\":\"Tool not available on macOS yet\"}"
                )
            }
        case .turnComplete:
            isAssistantSpeaking = false
            finalizeCurrentTurn()
        case .error(let message):
            // Tear down audio + event consumer BEFORE flipping state so the
            // mic doesn't stay hot capturing dead air after an upstream failure.
            // Previously we only updated `connectionState`, which left the
            // input tap + send timer running and kept the audio engine alive
            // indefinitely.
            stopAudioCapture()
            audioPlayer?.stop()
            eventConsumerTask?.cancel()
            eventConsumerTask = nil
            connectionState = .failed(message)
        }
    }

    private func finalizeCurrentTurn() {
        let user = userTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let assistant = assistantTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !user.isEmpty || !assistant.isEmpty {
            finalizedTurns.append((id: UUID(), user: user, assistant: assistant))
        }
        userTranscript = ""
        assistantTranscript = ""
    }

    // MARK: - Audio capture (macOS)

    private enum AudioCaptureSetup {
        case success(AVAudioEngine)
        case failed(String)
    }

    private func startAudioCapture() async {
        // Run engine creation + start off the main actor — AVAudioEngine.start() can take
        // several hundred ms, and we don't want the panel UI frozen during connect.
        let result: AudioCaptureSetup = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else {
                    cont.resume(returning: .failed("Voice session was cancelled"))
                    return
                }

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

                do {
                    engine.prepare()
                    try engine.start()
                } catch {
                    cont.resume(returning: .failed(
                        "Audio engine start failed: \(error.localizedDescription)"
                    ))
                    return
                }

                cont.resume(returning: .success(engine))
            }
        }

        switch result {
        case .success(let engine):
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

        // engine.stop() can stall briefly — keep teardown off-main so dismissing
        // the panel never feels sluggish.
        DispatchQueue.global(qos: .userInitiated).async {
            engineToStop?.stop()
            engineToStop?.inputNode.removeTap(onBus: 0)
        }
    }

    // MARK: - Microphone permission

    /// Resolves the user's mic-access status, requesting it on first call. Mirrors what
    /// the `MacVoiceInputButton` already does for speech-to-text so the live-voice path
    /// gets the same prompt instead of silently failing inside CoreAudio.
    private static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        @unknown default:
            return false
        }
    }

    // MARK: - System prompt

    private static func buildSystemPrompt(contextAboutYou: String, customInstructions: String) -> String {
        var lines: [String] = [
            "You are Todus, a friendly voice assistant.",
            "Keep replies concise and conversational — this is a spoken interaction, not a written one.",
            "Avoid bullet lists and markdown; speak in natural sentences.",
            "If the user asks for something requiring app actions, briefly acknowledge and tell them you can do it in the chat panel."
        ]
        let aboutYou = contextAboutYou.trimmingCharacters(in: .whitespacesAndNewlines)
        if !aboutYou.isEmpty {
            lines.append("")
            lines.append("About the user:")
            lines.append(aboutYou)
        }
        let custom = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            lines.append("")
            lines.append("Custom instructions:")
            lines.append(custom)
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Helper for converter callback

private final class _MutableBoolRef: @unchecked Sendable {
    var value: Bool = false
}

// MARK: - MacVoiceChatPanel (UI)

/// Sheet-style voice chat for the macOS app. Presented from the assistant panel
/// input bar (waveform button).
struct MacVoiceChatPanel: View {

    let chatService: MacAIChatService
    let tokenService: VoiceTokenService
    /// Optional shared services — when present we cooperate with the global
    /// voice coordinator so the in-panel session and the global hotkey/wake
    /// loop don't both try to grab the microphone (AVAudioEngine crashes
    /// with two simultaneous taps on the same input node).
    var services: MacAppServices? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: MacVoiceChatViewModel?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            transcriptArea
            Divider().opacity(0.4)
            Spacer(minLength: 8)
            centerIndicator
            Spacer(minLength: 12)
            controlBar
                .padding(.bottom, 18)
        }
        .frame(minWidth: 480, minHeight: 560)
        .background(MacTheme.contentBackground)
        .task {
            // Yield ownership of mic + WS to the panel for the duration of
            // this view. Previously this ran from `.onAppear` with two
            // unawaited tasks — the coordinator's `stop()` raced against the
            // panel's `vm.connect()`, sometimes producing a dual AVAudioEngine
            // attach on the same input node and a crash. Awaiting the stop
            // serialises ownership: coordinator down -> vm constructed -> vm up.
            if let services {
                await services.voiceCoordinator.stop()
            }
            let vm = MacVoiceChatViewModel(tokenService: tokenService, chatService: chatService)
            self.viewModel = vm
            await vm.connect()
        }
        .onDisappear {
            guard let vm = viewModel else { return }
            Task {
                await vm.disconnect()
                // Re-arm the global voice loop with the user's saved prefs
                // (hotkey-only or hotkey+wake) — the panel was a temporary
                // takeover, not a permanent disable.
                if let services { services.applyVoiceAssistantState() }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Live Voice")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(VoiceModelCatalog.gemini31FlashLiveDisplayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            connectionStatePill

            Button {
                Task {
                    await viewModel?.disconnect()
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(MacTheme.surfaceCard))
            }
            .buttonStyle(.plain)
            .help("Close")
            .accessibilityLabel("Close voice chat")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var connectionStatePill: some View {
        let (text, color) = connectionStateDisplay
        return Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var connectionStateDisplay: (String, Color) {
        guard let vm = viewModel else { return ("—", .secondary) }
        switch vm.connectionState {
        case .disconnected: return ("Disconnected", .secondary)
        case .connecting: return ("Connecting…", .orange)
        case .connected: return ("Listening", .green)
        case .reconnecting: return ("Reconnecting…", .orange)
        case .failed: return ("Error", .red)
        }
    }

    // MARK: Transcript

    private var transcriptArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let vm = viewModel {
                        ForEach(vm.finalizedTurns, id: \.id) { turn in
                            if !turn.user.isEmpty {
                                bubble(text: turn.user, role: .user, live: false)
                            }
                            if !turn.assistant.isEmpty {
                                bubble(text: turn.assistant, role: .assistant, live: false)
                            }
                        }
                        if !vm.userTranscript.isEmpty {
                            bubble(text: vm.userTranscript, role: .user, live: true)
                        }
                        if !vm.assistantTranscript.isEmpty {
                            bubble(text: vm.assistantTranscript, role: .assistant, live: true)
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel?.assistantTranscript) { _, _ in
                withAnimation(MacTheme.Motion.fast) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: viewModel?.finalizedTurns.count) { _, _ in
                withAnimation(MacTheme.Motion.fast) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .frame(maxHeight: 280)
    }

    private func bubble(text: String, role: TranscriptRole, live: Bool) -> some View {
        HStack {
            if role == .user { Spacer(minLength: 40) }
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    role == .user
                        ? Color.primary.opacity(0.10)
                        : MacTheme.surfaceCard,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .opacity(live ? 0.75 : 1)
            if role == .assistant { Spacer(minLength: 40) }
        }
    }

    // MARK: Center indicator

    private var centerIndicator: some View {
        VStack(spacing: 10) {
            ZStack {
                if viewModel?.isAssistantSpeaking == true {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(aiGradient, lineWidth: 2)
                            .frame(width: CGFloat(70 + i * 20), height: CGFloat(70 + i * 20))
                            .opacity(0.3 - Double(i) * 0.1)
                    }
                }

                Circle()
                    .fill(MacTheme.surfaceCard)
                    .frame(width: 64, height: 64)
                    .overlay(Circle().stroke(MacTheme.cardBorder, lineWidth: 1))
                    .overlay { stateIcon }
            }
            .frame(height: 110)

            Text(stateLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MacTheme.mutedText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    private var stateIcon: some View {
        Group {
            switch viewModel?.connectionState {
            case .connecting, .reconnecting:
                ProgressView().controlSize(.small)
            case .connected:
                if viewModel?.isAssistantSpeaking == true {
                    Image(systemName: "waveform")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(aiGradient)
                } else {
                    Image(systemName: "ear")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                }
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.red)
            default:
                Image(systemName: "waveform")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(MacTheme.mutedText)
            }
        }
    }

    private var stateLabel: String {
        guard let vm = viewModel else { return "" }
        switch vm.connectionState {
        case .connecting: return "Connecting…"
        case .reconnecting: return "Reconnecting…"
        case .connected:
            if vm.isAssistantSpeaking { return "Speaking…" }
            if vm.isMicMuted { return "Muted" }
            return "Listening…"
        case .failed(let msg): return msg
        case .disconnected: return "Disconnected"
        }
    }

    // MARK: Controls

    private var controlBar: some View {
        HStack(spacing: 32) {
            Button {
                viewModel?.toggleMute()
            } label: {
                ZStack {
                    Circle()
                        .fill(viewModel?.isMicMuted == true ? Color.red.opacity(0.15) : MacTheme.surfaceCard)
                        .frame(width: 52, height: 52)
                        .overlay(
                            Circle().stroke(
                                viewModel?.isMicMuted == true ? Color.red.opacity(0.4) : MacTheme.cardBorder,
                                lineWidth: 1
                            )
                        )
                    Image(systemName: viewModel?.isMicMuted == true ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(viewModel?.isMicMuted == true ? .red : .primary)
                }
            }
            .buttonStyle(.plain)
            .help(viewModel?.isMicMuted == true ? "Unmute" : "Mute")
            .accessibilityLabel(viewModel?.isMicMuted == true ? "Unmute microphone" : "Mute microphone")

            Button {
                Task {
                    await viewModel?.disconnect()
                    dismiss()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 52, height: 52)
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .help("End")
            .accessibilityLabel("End call")
        }
    }

    // MARK: Gradient (matches iOS)

    private var aiGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0, green: 0xAA / 255.0, blue: 0xF5 / 255.0), location: 0.087),
                .init(color: Color(red: 0xEF / 255.0, green: 0, blue: 0xC2 / 255.0), location: 0.269),
                .init(color: Color(red: 1, green: 0, blue: 0x38 / 255.0), location: 0.580),
                .init(color: Color(red: 0xF9 / 255.0, green: 0x9F / 255.0, blue: 0), location: 0.913),
            ],
            startPoint: UnitPoint(x: 0.25, y: 0),
            endPoint: UnitPoint(x: 0.75, y: 1)
        )
    }
}

// MARK: - MacAIChatService voice convenience

extension MacAIChatService {
    /// Append a finalized voice exchange to the chat history. The macOS chat shows it
    /// in the same scrollback as text messages so the conversation is unified.
    func appendVoiceExchange(userText: String, assistantText: String) {
        let trimmedUser = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAssistant = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedUser.isEmpty {
            messages.append(MacChatMessage(role: .user, content: trimmedUser))
        }
        if !trimmedAssistant.isEmpty {
            messages.append(MacChatMessage(role: .assistant, content: trimmedAssistant))
        }
    }
}

