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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]

    @State private var viewModel: VoiceChatViewModel?
    @State private var textInput = ""
    @State private var isDisconnecting = false
    /// Briefly shows a "Done" success capsule after a tool call finishes without
    /// error, instead of the status just vanishing with no confirmation.
    @State private var showsToolCallSuccess = false

    private var isFailed: Bool {
        if case .failed = viewModel?.connectionState { return true }
        return false
    }

    var body: some View {
        ZStack {
            // Full-screen background
            AppTheme.sheetBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                transcriptArea
                Spacer(minLength: 16)
                if isFailed {
                    errorCard
                } else {
                    centerIndicator
                    toolCallStatusView
                }
                if isDisconnecting {
                    Text("Closing…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.mutedText)
                        .transition(.opacity)
                        .padding(.bottom, 8)
                }
                Spacer(minLength: 24)
                if isFailed {
                    errorControlBar
                } else {
                    controlBar
                }
            }
            .padding(.bottom, 16)
            .animation(.easeOut(duration: 0.15), value: isDisconnecting)
        }
        .onChange(of: viewModel?.toolCallStatus) { oldValue, newValue in
            // A non-nil status that clears without ever containing "failed" reads as
            // a successful tool call — show a brief "Done" confirmation instead of
            // letting the capsule just vanish.
            guard newValue == nil, let old = oldValue, !old.lowercased().contains("fail") else { return }
            withAnimation(.snappy(duration: 0.15)) {
                showsToolCallSuccess = true
            }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.easeOut(duration: 0.15)) {
                    showsToolCallSuccess = false
                }
            }
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
                closeAndDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.surfaceSecondary, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isDisconnecting)
            .opacity(isDisconnecting ? 0.5 : 1.0)
            .accessibilityLabel("Close voice chat")

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
                            // Reduce Motion: static rings instead of pulsing (TD-11).
                            .scaleEffect(viewModel?.isAssistantSpeaking == true && !reduceMotion ? 1.1 : 1.0)
                            .animation(
                                reduceMotion
                                    ? nil
                                    : .easeInOut(duration: 1.2)
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
                .transition(.opacity)
                .animation(.easeOut(duration: 0.18), value: stateLabel)
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
                } else if viewModel?.isMicMuted == true {
                    Image(systemName: "mic.slash")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(AppTheme.mutedText)
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
        .transition(.opacity)
        .animation(.easeOut(duration: 0.18), value: viewModel?.isMicMuted)
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

    // MARK: - Error Card (connection failure)

    /// Shown in place of the normal center indicator when `connectionState == .failed`.
    /// Regular (non-dev) users previously saw a blank listening indicator with no
    /// recovery path on connection failure — this surfaces the error + retry/close.
    private var errorCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.red)

            Text("Couldn't connect")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            if case .failed(let message) = viewModel?.connectionState {
                Text(message)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(AppTheme.mutedText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }
        }
        .padding(.vertical, 24)
        .transition(.opacity)
    }

    private var errorControlBar: some View {
        HStack(spacing: 16) {
            Button {
                closeAndDismiss()
            } label: {
                Text("Close")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isDisconnecting)

            Button {
                Task { await viewModel?.connect() }
            } label: {
                Text("Retry")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isDisconnecting)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Dismiss Helpers

    /// Shared close path for the header close button and the "Close" button in the
    /// error state. Shows a brief "Closing…" state via `isDisconnecting` before
    /// dismissing so the user gets feedback instead of an instant, silent close.
    private func closeAndDismiss() {
        guard !isDisconnecting else { return }
        isDisconnecting = true
        Task {
            await viewModel?.disconnect()
            dismiss()
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
        } else if showsToolCallSuccess {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Done")
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
            .sensoryFeedback(.selection, trigger: viewModel?.isMicMuted)

            // End call — red circle
            Button {
                closeAndDismiss()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 64, height: 64)

                    if isDisconnecting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isDisconnecting)
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
