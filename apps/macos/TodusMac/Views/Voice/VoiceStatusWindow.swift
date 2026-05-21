import SwiftUI

// MARK: - VoiceStatusWindow

/// Floating status panel for the always-on voice loop. Shows the current
/// state, the live transcript, the last assistant reply, and the last tool
/// call. Used as a thin observability surface — full chat UI still lives
/// in `MacVoiceChatPanel`.
///
/// Brought to front when the coordinator transitions to `.triggered` (wake
/// word fired or hotkey pressed) so the user has immediate visual feedback
/// without having to open the assistant panel.
struct VoiceStatusWindow: View {
    let coordinator: VoiceSessionCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider().opacity(0.4)
            transcriptSection
            Spacer(minLength: 0)
            footer
        }
        .padding(18)
        .frame(width: 360, height: 320)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            stateDot
            VStack(alignment: .leading, spacing: 2) {
                Text("Todus Voice")
                    .font(.system(size: 14, weight: .semibold))
                Text(stateDescription)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let trigger = coordinator.activeTrigger {
                Text(trigger.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(.secondary)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
    }

    private var stateDot: some View {
        Circle()
            .fill(stateColor)
            .frame(width: 10, height: 10)
            .overlay(Circle().strokeBorder(stateColor.opacity(0.4), lineWidth: 2).blur(radius: 1))
    }

    private var stateDescription: String {
        switch coordinator.state {
        case .idle: return "Idle — press ⌘⇧Space to talk"
        case .wakeListening: return "Listening for wake word"
        case .triggered: return "Connecting…"
        case .recording: return "Listening"
        case .thinking: return "Thinking"
        case .speaking: return "Speaking"
        case .toolRunning(let name): return "Running \(name)"
        case .interrupted: return "Interrupted"
        case .error(let msg): return "Error: \(msg)"
        case .sleeping: return "Sleeping"
        }
    }

    private var stateColor: Color {
        switch coordinator.state {
        case .idle, .sleeping: return .gray
        case .wakeListening: return .blue
        case .triggered: return .orange
        case .recording: return .green
        case .thinking, .toolRunning: return .yellow
        case .speaking: return .purple
        case .interrupted: return .orange
        case .error: return .red
        }
    }

    // MARK: - Transcript

    private var transcriptSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(coordinator.finalizedTurns) { turn in
                    if !turn.user.isEmpty {
                        TranscriptBubble(text: turn.user, role: .user, live: false)
                    }
                    if !turn.assistant.isEmpty {
                        TranscriptBubble(text: turn.assistant, role: .assistant, live: false)
                    }
                }
                if !coordinator.userTranscript.isEmpty {
                    TranscriptBubble(text: coordinator.userTranscript, role: .user, live: true)
                }
                if !coordinator.assistantTranscript.isEmpty {
                    TranscriptBubble(text: coordinator.assistantTranscript, role: .assistant, live: true)
                }
                if coordinator.finalizedTurns.isEmpty
                    && coordinator.userTranscript.isEmpty
                    && coordinator.assistantTranscript.isEmpty {
                    Text("No transcript yet.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if let tool = coordinator.lastToolCall {
                Label("Last tool: \(tool)", systemImage: "wrench.and.screwdriver")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("End") {
                Task { await coordinator.disconnect(reason: "user closed status window") }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(coordinator.activeTrigger == nil)
            // Surface why the button is grayed out without making the user guess.
            .help(coordinator.activeTrigger == nil ? "No active session" : "End session")
        }
    }
}

// MARK: - TranscriptBubble

private struct TranscriptBubble: View {
    enum Role { case user; case assistant }

    let text: String
    let role: Role
    let live: Bool

    var body: some View {
        HStack {
            if role == .user { Spacer(minLength: 24) }
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    role == .user ? Color.primary.opacity(0.10) : Color.secondary.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .opacity(live ? 0.75 : 1)
            if role == .assistant { Spacer(minLength: 24) }
        }
    }
}
