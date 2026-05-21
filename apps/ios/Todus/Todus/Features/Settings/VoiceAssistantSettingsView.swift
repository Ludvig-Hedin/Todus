import SwiftUI

// MARK: - VoiceAssistantSettingsView (iOS)
//
// Mirrors the macOS `voiceAssistantSection` in `MacSettingsView` (the toggle
// row + the supporting context) using iOS-native form patterns. Reached via a
// new NavigationLink in `SettingsView.preferencesSection`.

struct VoiceAssistantSettingsView: View {
    @Environment(AppServices.self) private var services

    // Persisted flags. Keys are scoped under TaskApp.* to match the rest of
    // the app's UserDefaults conventions in AppServices.swift.
    @AppStorage("TaskApp.voiceAssistantEnabled") private var voiceAssistantEnabled: Bool = true
    @AppStorage("TaskApp.voiceAutoStopIdleEnabled") private var voiceAutoStopIdleEnabled: Bool = false

    /// Touched after a successful "Reset voice persona cache" tap so we can
    /// briefly show a confirmation hint inline. Auto-clears after a few seconds.
    @State private var didResetPersonaCacheAt: Date?

    var body: some View {
        List {
            enableSection
            triggerSection
            personaSection
            statusSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.sheetBackground)
        .navigationTitle("Voice Assistant")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Sections

    private var enableSection: some View {
        Section {
            Toggle(isOn: $voiceAssistantEnabled) {
                Label("Enable voice assistant", systemImage: "waveform")
            }
            .tint(AppTheme.switchTint)
            .accessibilityIdentifier("voice.settings.enableToggle")

            Toggle(isOn: $voiceAutoStopIdleEnabled) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-stop after 30s idle")
                        Text("Closes the session after 30 seconds with no speech.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "timer")
                }
            }
            .tint(AppTheme.switchTint)
            .disabled(!voiceAssistantEnabled)
        } header: {
            Text("Voice Assistant")
        } footer: {
            Text("Talk to Todus from anywhere using the Siri Shortcut below. Mic permission is requested the first time you start a session.")
        }
    }

    private var triggerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "command")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Voice trigger")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text("Open the Shortcuts app and add the **Start Voice Assistant** shortcut. You can then bind it to the Action Button, the Lock Screen, or a Siri phrase.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let shortcutsURL = URL(string: "shortcuts://") {
                    Link(destination: shortcutsURL) {
                        Label("Open Shortcuts", systemImage: "arrow.up.right.square")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Trigger")
        }
    }

    private var personaSection: some View {
        Section {
            Button {
                services.voiceSystemPromptClient.invalidateCache()
                didResetPersonaCacheAt = Date()
                // Auto-clear the confirmation hint after a few seconds.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if let at = didResetPersonaCacheAt,
                       Date().timeIntervalSince(at) >= 4 {
                        didResetPersonaCacheAt = nil
                    }
                }
            } label: {
                Label("Reset voice persona cache", systemImage: "arrow.clockwise")
            }

            if didResetPersonaCacheAt != nil {
                Text("Cache cleared — the next voice session will fetch a fresh persona and memories.")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
        } header: {
            Text("Persona")
        } footer: {
            Text("The voice persona is built on the server from your custom instructions and recent memories. Reset if your last memory hasn't been picked up.")
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section {
            LabeledContent("Last status") {
                Text(statusLabel(for: services.voiceSessionCoordinator.status))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(statusColor(for: services.voiceSessionCoordinator.status))
            }
            if let err = services.voiceSessionCoordinator.lastError, !err.isEmpty {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Connection")
        } footer: {
            Text("Shows the latest state of the live voice session.")
        }
    }

    // MARK: - Helpers

    private func statusLabel(for status: VoiceSessionStatus) -> String {
        switch status {
        case .idle: return "Idle"
        case .connecting: return "Connecting…"
        case .listening: return "Listening"
        case .speaking: return "Speaking"
        case .toolRunning(let name): return "Running \(name.replacingOccurrences(of: "_", with: " "))…"
        case .error: return "Error"
        }
    }

    private func statusColor(for status: VoiceSessionStatus) -> Color {
        switch status {
        case .idle: return .secondary
        case .connecting: return .orange
        case .listening, .speaking, .toolRunning: return .green
        case .error: return AppTheme.danger
        }
    }
}
