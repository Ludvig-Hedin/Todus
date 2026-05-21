import AppKit
import Carbon.HIToolbox
import Foundation

// MARK: - HotkeyService

/// Global push-to-talk hotkey for the macOS voice assistant.
///
/// Uses Carbon `RegisterEventHotKey` because:
///   • It works inside the App Sandbox without any extra entitlement
///     (Input Monitoring permission, which `NSEvent.addGlobalMonitor`
///     would need on Sequoia+, is intrusive to ask for).
///   • It receives BOTH key-down and key-up events, which we need for
///     true push-to-talk semantics (start streaming on press, finish
///     the turn on release). `NSEvent.addGlobalMonitor` only receives
///     key-down events.
///
/// Default chord: ⌘⇧Space. Held to record, released to send the turn.
@MainActor
final class HotkeyService {

    // MARK: - Public

    /// Fires when the chord is pressed.
    var onPress: (@MainActor () -> Void)?
    /// Fires when the chord is released.
    var onRelease: (@MainActor () -> Void)?

    /// True if the hotkey is currently registered with the OS.
    private(set) var isRegistered: Bool = false

    // MARK: - Carbon glue

    private var pressHandlerRef: EventHandlerRef?
    private var releaseHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?

    /// Each callback registration uses a 4-char ID. Pick something distinctive
    /// so it doesn't collide with other Carbon clients in-process.
    private static let hotKeyIDSignature: OSType = 0x544F4455 // 'TODU'
    private static let hotKeyIDValue: UInt32 = 1

    // MARK: - Lifecycle

    /// Register the default chord (⌘⇧Space). Idempotent — repeat calls are no-ops.
    func register() {
        guard !isRegistered else { return }

        // Install Carbon event handlers BEFORE registering the hotkey, so a
        // very fast first press doesn't slip through unhandled.
        installEventHandlers()

        let hotKeyID = EventHotKeyID(signature: Self.hotKeyIDSignature, id: Self.hotKeyIDValue)
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
        let keyCode: UInt32 = UInt32(kVK_Space)

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKeyRef = ref
            isRegistered = true
            AppLogger.shared.log("[HotkeyService] registered ⌘⇧Space push-to-talk")
        } else {
            AppLogger.shared.log("[HotkeyService] RegisterEventHotKey failed (status \(status))")
            uninstallEventHandlers()
        }
    }

    /// Unregister and tear down handlers. Safe to call repeatedly.
    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        uninstallEventHandlers()
        isRegistered = false
    }

    // Intentionally NO deinit. Swift 6 nonisolated deinit cannot touch the
    // non-Sendable Carbon `EventHotKeyRef` / `EventHandlerRef` handles, so
    // teardown happens explicitly via `unregister()` (called from
    // `MacAppServices.signOut` / `applyVoiceAssistantState`). The hotkey
    // service is owned by `MacAppServices` for the app's lifetime, so the
    // OS reclaims the registration on process exit if `unregister()` was
    // never called.

    // MARK: - Carbon handler installation

    private func installEventHandlers() {
        var pressSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var releaseSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyReleased)
        )

        // Pass `self` as user data via Unmanaged so the C callback can hop
        // back into Swift. Carbon callbacks are NOT @MainActor, so the
        // callback dispatches onto the main queue before touching `self`.
        let userData = Unmanaged.passUnretained(self).toOpaque()

        var pressRef: EventHandlerRef?
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
                let matched = HotkeyService.eventMatchesOurID(eventRef)
                if matched {
                    DispatchQueue.main.async {
                        service.onPress?()
                    }
                    return noErr
                }
                return OSStatus(eventNotHandledErr)
            },
            1,
            &pressSpec,
            userData,
            &pressRef
        )
        pressHandlerRef = pressRef

        var releaseRef: EventHandlerRef?
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
                let matched = HotkeyService.eventMatchesOurID(eventRef)
                if matched {
                    DispatchQueue.main.async {
                        service.onRelease?()
                    }
                    return noErr
                }
                return OSStatus(eventNotHandledErr)
            },
            1,
            &releaseSpec,
            userData,
            &releaseRef
        )
        releaseHandlerRef = releaseRef
    }

    private func uninstallEventHandlers() {
        if let pressHandlerRef {
            RemoveEventHandler(pressHandlerRef)
            self.pressHandlerRef = nil
        }
        if let releaseHandlerRef {
            RemoveEventHandler(releaseHandlerRef)
            self.releaseHandlerRef = nil
        }
    }

    /// Ensures the Carbon event we just received is OURS. Other clients in
    /// the process (Spotlight competitors, accessibility apps) can register
    /// their own hotkeys; without this filter we'd react to all of them.
    private static func eventMatchesOurID(_ eventRef: EventRef?) -> Bool {
        guard let eventRef else { return false }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return false }
        return hotKeyID.signature == hotKeyIDSignature && hotKeyID.id == hotKeyIDValue
    }
}
