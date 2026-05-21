import Foundation

// MARK: - WakeWordService

/// Always-listening wake-word detector.
///
/// Phase 1 ships as a **stub** that fails-soft: it logs `[Wake] disabled —
/// hotkey only` and never fires. The real implementation will plug into
/// Picovoice Porcupine via SPM (`https://github.com/Picovoice/porcupine`)
/// using the built-in `"computer"` keyword (NOT custom "Hey Todus" — see
/// docs/voice/PHASE_1.md for the rationale).
///
/// Why a stub now:
///   • Porcupine SPM adds an arm64 binary dependency and a Picovoice
///     AccessKey signup step. Shipping Phase 1 without it keeps the build
///     reproducible and unblocks the rest of the voice loop.
///   • The interface here is what the eventual Porcupine wrapper must
///     conform to, so dropping in the real detector later is a one-file
///     change.
///
/// To enable real wake-word detection in Phase 1.5:
///   1) Add `Porcupine` to project.yml under TodusMac.packages
///   2) Set `PORCUPINE_ACCESS_KEY` in the user's Keychain via Settings
///   3) Replace the stub `start()` with a Porcupine recognizer that
///      consumes 16kHz Int16 frames from `AudioInputBroker`.
@MainActor
final class WakeWordService {

    // MARK: - Public

    /// Fires when the wake word is detected.
    var onDetected: (@MainActor () -> Void)?

    /// True while detection is active.
    private(set) var isListening: Bool = false

    /// Last reason why detection isn't running. `nil` while listening or
    /// before the first `start()` attempt. Useful for surfacing in Settings.
    private(set) var lastDisabledReason: String?

    // MARK: - State

    private weak var broker: AudioInputBroker?
    private var brokerToken: UUID?

    // MARK: - Public API

    init(broker: AudioInputBroker) {
        self.broker = broker
    }

    /// Start listening for the wake word. Stub implementation: logs and
    /// returns false. The seam to the real Porcupine implementation is the
    /// `attachToBroker(accessKey:)` call below.
    @discardableResult
    func start() async -> Bool {
        guard !isListening else { return true }

        let accessKey = readPorcupineAccessKey()
        guard let accessKey, !accessKey.isEmpty else {
            lastDisabledReason = "Porcupine access key not configured. Always-listening disabled — push-to-talk still works."
            AppLogger.shared.log("[WakeWordService] disabled — hotkey only (no PORCUPINE_ACCESS_KEY)")
            return false
        }

        // Real implementation lands here in Phase 1.5. For now we acknowledge
        // the key but explicitly bail out — Porcupine SPM is not in
        // project.yml. See class doc above for the enablement steps.
        lastDisabledReason = "Wake word integration pending — Porcupine SPM not yet linked. Hotkey works."
        AppLogger.shared.log("[WakeWordService] disabled — Porcupine SPM not linked (Phase 1.5)")
        return false
    }

    /// Stop listening. Always safe to call.
    func stop() {
        guard isListening else { return }
        if let broker, let brokerToken {
            broker.removeConsumer(brokerToken)
        }
        brokerToken = nil
        isListening = false
        AppLogger.shared.log("[WakeWordService] stopped")
    }

    // MARK: - Private

    /// Reads the Porcupine access key from the user's Keychain. Falls back
    /// to a UserDefaults entry for development.
    ///
    /// In production this should ONLY come from the Keychain — UserDefaults
    /// is included so a developer can drop the key in via the Settings UI
    /// without dealing with the Keychain dialog on first run.
    private func readPorcupineAccessKey() -> String? {
        let defaultsKey = "Voice.PorcupineAccessKey"
        if let stored = UserDefaults.standard.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !stored.isEmpty {
            return stored
        }
        // Future: query Keychain here when Settings UI is wired.
        return nil
    }
}
