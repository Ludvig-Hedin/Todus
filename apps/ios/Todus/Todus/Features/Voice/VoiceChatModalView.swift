import SwiftUI
import SwiftData

// MARK: - VoiceChatModalView

/// Full-screen modal for live voice chat. Presented from the AI chat input bar.
///
/// Layout:
/// - Header: title, connection state pill (dev mode), close button
/// - Transcript scroll area: finalized turns + live partial transcripts
/// - Center: animated listening/speaking indicator
/// - Tool call status capsule
/// - Bottom controls: mic mute/unmute, end call
struct VoiceChatModalView: View {

    let chatService: AIChatService
    let tokenService: VoiceTokenService

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Query(sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]

    @State private var viewModel: VoiceChatViewModel?
    @State private var textInput = ""

    var body: some View {
        ZStack {
            // Full-screen background
            AppTheme.sheetBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                transcriptArea
                Spacer(minLength: 16)
                centerIndicator
                toolCallStatusView
                Spacer(minLength: 24)
                controlBar
            }
            .padding(.bottom, 16)
        }
        .onAppear {
            let vm = VoiceChatViewModel(tokenService: tokenService, chatService: chatService)
            vm.allTasks = allTasks
            vm.modelContext = modelContext
            self.viewModel = vm
            Task { await vm.connect() }
        }
        .onDisappear {
            guard let vm = viewModel else { return }
            Task { await vm.disconnect() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            // Close button
            Button {
                Task {
                    await viewModel?.disconnect()
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.surfaceSecondary, in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text("Live Voice")
                    .font(.system(size: 17, weight: .semibold))
                Text("Gemini 3.1 Flash Live")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.mutedText)
            }

            Spacer()

            // Dev mode: show connection state
            if services.effectiveDeveloperModeEnabled {
                connectionStatePill
            } else {
                // Invisible spacer to keep title centered
                Color.clear.frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var connectionStatePill: some View {
        let (text, color) = connectionStateDisplay
        return Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var connectionStateDisplay: (String, Color) {
        guard let vm = viewModel else { return ("—", .secondary) }
        switch vm.connectionState {
        case .disconnected: return ("Disconnected", .secondary)
        case .connecting: return ("Connecting…", .orange)
        case .connected: return ("Connected", .green)
        case .reconnecting: return ("Reconnecting…", .orange)
        case .failed(let msg): return ("Error: \(msg.prefix(20))", .red)
        }
    }

    // MARK: - Transcript Area

    private var transcriptArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    // Finalized turns
                    if let vm = viewModel {
                        ForEach(vm.finalizedTurns, id: \.id) { turn in
                            if !turn.user.isEmpty {
                                transcriptBubble(text: turn.user, role: .user)
                            }
                            if !turn.assistant.isEmpty {
                                transcriptBubble(text: turn.assistant, role: .assistant)
                            }
                        }

                        // Live partial transcripts
                        if !vm.userTranscript.isEmpty {
                            transcriptBubble(text: vm.userTranscript, role: .user, isLive: true)
                        }
                        if !vm.assistantTranscript.isEmpty {
                            transcriptBubble(text: vm.assistantTranscript, role: .assistant, isLive: true)
                        }
                    }

                    // Anchor for auto-scroll
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel?.assistantTranscript) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: viewModel?.finalizedTurns.count) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private func transcriptBubble(text: String, role: TranscriptRole, isLive: Bool = false) -> some View {
        HStack {
            if role == .user { Spacer(minLength: 60) }

            VStack(alignment: role == .user ? .trailing : .leading, spacing: 4) {
                if isLive {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(role == .user ? Color.primary.opacity(0.85) : Color.green)
                            .frame(width: 6, height: 6)
                        Text(role == .user ? "You" : "AI")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.mutedText)
                    }
                }

                Text(text)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(role == .user ? .trailing : .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        role == .user
                            ? Color.primary.opacity(0.12)
                            : AppTheme.surfacePrimary,
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                            .stroke(
                                role == .user ? Color.primary.opacity(0.2) : AppTheme.cardBorder,
                                lineWidth: 1
                            )
                    )
                    .opacity(isLive ? 0.8 : 1)
            }

            if role == .assistant { Spacer(minLength: 60) }
        }
    }

    // MARK: - Center Indicator

    private var centerIndicator: some View {
        VStack(spacing: 12) {
            ZStack {
                // Pulsating rings when assistant is speaking
                if viewModel?.isAssistantSpeaking == true {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(aiGradient, lineWidth: 2)
                            .frame(width: CGFloat(80 + i * 24), height: CGFloat(80 + i * 24))
                            .opacity(0.3 - Double(i) * 0.1)
                            .scaleEffect(viewModel?.isAssistantSpeaking == true ? 1.1 : 0.9)
                            .animation(
                                .easeInOut(duration: 1.2)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.2),
                                value: viewModel?.isAssistantSpeaking
                            )
                    }
                }

                // Center circle with state icon
                Circle()
                    .fill(AppTheme.surfacePrimary)
                    .frame(width: 72, height: 72)
                    .overlay(Circle().stroke(AppTheme.strongBorder, lineWidth: 1))
                    .overlay {
                        stateIcon
                    }
            }
            .frame(height: 140)

            // State label
            Text(stateLabel)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
        }
    }

    private var stateIcon: some View {
        Group {
            switch viewModel?.connectionState {
            case .connecting, .reconnecting:
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(AppTheme.mutedText)
            case .connected:
                if viewModel?.isAssistantSpeaking == true {
                    Image(systemName: "waveform")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(aiGradient)
                } else {
                    Image(systemName: "ear")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(AppTheme.mutedText)
                }
            case .failed:
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.red)
            default:
                Image(systemName: "waveform")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(AppTheme.mutedText)
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

    // MARK: - Tool Call Status

    @ViewBuilder
    private var toolCallStatusView: some View {
        if let status = viewModel?.toolCallStatus {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(AppTheme.mutedText)
                Text(status)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.subtleText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(AppTheme.surfaceSecondary, in: Capsule())
            .transition(.scale.combined(with: .opacity))
            .padding(.top, 8)
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 40) {
            // Mic mute/unmute — large circle
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    viewModel?.toggleMute()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(viewModel?.isMicMuted == true ? Color.red.opacity(0.15) : AppTheme.surfacePrimary)
                        .frame(width: 64, height: 64)
                        .overlay(
                            Circle().stroke(
                                viewModel?.isMicMuted == true ? Color.red.opacity(0.4) : AppTheme.strongBorder,
                                lineWidth: 1.5
                            )
                        )

                    Image(systemName: viewModel?.isMicMuted == true ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(viewModel?.isMicMuted == true ? .red : .primary)
                }
            }
            .buttonStyle(.plain)

            // End call — red circle
            Button {
                Task {
                    await viewModel?.disconnect()
                    dismiss()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 64, height: 64)

                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - AI Gradient (reused from CustomTabBar design)

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
