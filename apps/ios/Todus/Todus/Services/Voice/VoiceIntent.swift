import AppIntents
import Foundation

// MARK: - Notification name

extension Notification.Name {
    /// Posted by `StartVoiceAssistantIntent.perform()` so the running app can
    /// catch it and call `VoiceSessionCoordinator.start()`. Subscribed in
    /// `TodosApp` (see `subscribeToVoiceSessionStartTrigger`).
    static let todusStartVoiceSession = Notification.Name("TodusStartVoiceSession")
}

// MARK: - StartVoiceAssistantIntent

/// AppIntent exposed to Siri Shortcuts so users can launch the Todus voice
/// assistant from the Action Button, Lock Screen, watchOS, or by saying
/// "Hey Siri, start voice assistant" (when the user binds a phrase). The
/// intent itself is intentionally tiny — it just opens the app and posts
/// `Notification.Name.todusStartVoiceSession`. The session lifecycle is
/// owned by `VoiceSessionCoordinator` so behaviour stays identical whether
/// the trigger came from the in-app modal, Settings, or this intent.
@available(iOS 16.0, *)
struct StartVoiceAssistantIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Voice Assistant"
    static let description = IntentDescription(
        "Open Todus and start a live voice conversation with the assistant."
    )

    /// `openAppWhenRun = true` so the system foregrounds Todus before the
    /// performed action runs. The voice coordinator depends on AVAudioEngine
    /// (mic access) and the SwiftData ModelContext both of which require the
    /// app to be in the foreground.
    static let openAppWhenRun: Bool = true

    /// Hint to the system that this intent is safe to surface as a Shortcut
    /// and Spotlight result without further setup.
    static let isDiscoverable: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: .todusStartVoiceSession,
            object: nil
        )
        return .result()
    }
}

// MARK: - App Shortcuts provider

/// Surfaces `StartVoiceAssistantIntent` under Settings → Shortcuts (and the
/// Shortcuts app) immediately after install, so the user doesn't have to
/// create a custom Shortcut to wire up the Action Button.
@available(iOS 16.0, *)
struct TodusVoiceAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartVoiceAssistantIntent(),
            phrases: [
                "Start \(.applicationName) voice assistant",
                "Talk to \(.applicationName)",
                "Open \(.applicationName) voice"
            ],
            shortTitle: "Start Voice Assistant",
            systemImageName: "waveform"
        )
    }
}
