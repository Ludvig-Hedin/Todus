import Foundation
import Observation

/// Coordinates microphone ownership between the modal `VoiceChatViewModel`
/// and the system-wide `VoiceSessionCoordinator`. Both can be triggered
/// independently (modal open + Siri Shortcut firing). Without this lock,
/// two AVAudioEngine instances try to attach the same input node — same
/// class of bug as H17 (double-attach crash).
///
/// The lock is cooperative: each owner asks before grabbing the mic and
/// releases on stop. The lock does not physically prevent AVAudioEngine
/// from running — it just exposes a single source of truth so both code
/// paths can refuse to start when the mic is already held.
@MainActor
@Observable
final class VoiceMicLock {
    /// Current owner identifier (e.g. "coordinator", "modal"), or nil if free.
    private(set) var owner: String?

    init() {}

    /// Attempt to grab the lock for `owner`. Returns true if acquired (or
    /// already held by the same owner — idempotent). Returns false if a
    /// different owner currently holds it.
    func acquire(owner: String) -> Bool {
        if let current = self.owner {
            return current == owner
        }
        self.owner = owner
        return true
    }

    /// Release the lock IF the caller is the current owner. No-op otherwise
    /// so a stale stop() can't yank the mic from a different active session.
    func release(owner: String) {
        if self.owner == owner {
            self.owner = nil
        }
    }

    /// Whether the lock is currently held by anyone.
    var isHeld: Bool { owner != nil }
}
