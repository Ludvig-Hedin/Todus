import Foundation

/// Per-connection email signature persistence backed by UserDefaults.
/// Mirrors the iOS signature feature so macOS compose can auto-append a sign-off
/// when the user starts a new draft.
///
/// Keys are namespaced by connectionId so multi-account users can keep separate
/// signatures per mailbox. Empty / whitespace-only signatures are treated as
/// "no signature" and removed from storage to keep `signature(for:)` honest.
@MainActor
final class MacSignatureStore {
    static let shared = MacSignatureStore()

    private let defaults: UserDefaults
    private static let keyPrefix = "mac_email_signature_v1."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Returns the trimmed signature for the given connection, or empty string when none is set.
    /// Empty connectionId returns "" so callers don't have to guard themselves.
    func signature(for connectionId: String) -> String {
        let id = connectionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return "" }
        return defaults.string(forKey: storageKey(for: id)) ?? ""
    }

    /// Saves a signature for the given connection. Empty / whitespace-only values
    /// remove the entry so we don't append a phantom "\n\n-- \n" block to outbound mail.
    func setSignature(_ value: String, for connectionId: String) {
        let id = connectionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: storageKey(for: id))
        } else {
            defaults.set(trimmed, forKey: storageKey(for: id))
        }
    }

    /// Convenience helper used by the compose view — formats the signature with the
    /// standard `\n\n-- \n` separator that mail clients recognise. Returns nil when
    /// there is no signature to append so callers can short-circuit cleanly.
    func formattedSignatureBlock(for connectionId: String) -> String? {
        let sig = signature(for: connectionId)
        guard !sig.isEmpty else { return nil }
        return "\n\n-- \n\(sig)"
    }

    private func storageKey(for connectionId: String) -> String {
        "\(Self.keyPrefix)\(connectionId)"
    }
}
