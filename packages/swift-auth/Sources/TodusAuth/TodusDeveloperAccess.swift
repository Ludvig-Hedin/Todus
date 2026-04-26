import Foundation

/// Gates Developer Mode UI (settings toggle, debug sections) to specific accounts.
public enum TodusDeveloperAccess {
    /// Comma-separated emails, lowercased at runtime. Set `TODUS_ALLOWLISTED_EMAILS` in the Xcode
    /// scheme, `launchctl setenv` (simulator), or the process environment; default is empty.
    public static var allowlistedEmails: Set<String> {
        let raw = ProcessInfo.processInfo.environment["TODUS_ALLOWLISTED_EMAILS"] ?? ""
        if raw.isEmpty { return [] }
        let parts = raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return Set(parts)
    }

    public static func isAllowlisted(email: String?) -> Bool {
        guard let normalized = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty else {
            return false
        }
        return allowlistedEmails.contains(normalized)
    }
}
