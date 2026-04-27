import Foundation

/// Disk-backed cache for assistant data so the Home screen can render real content
/// on cold launch instead of flashing skeletons. Mirrors the inbox-thread cache
/// pattern in EmailService — JSON-encoded payload + timestamp pair in UserDefaults.
///
/// Stale-after only controls the refresh signal; cached payloads are always returned
/// when present so the UI never blanks out while the background refresh runs.
enum AssistantPersistedCache {
    private static let briefingDataKey = "assistant_briefing_v1"
    private static let briefingTimestampKey = "assistant_briefing_v1_ts"
    private static let nudgesDataKey = "assistant_nudges_v1"
    private static let nudgesTimestampKey = "assistant_nudges_v1_ts"

    /// Refresh after this age, but still serve the cached payload until new data arrives.
    static let maxAge: TimeInterval = 1800

    // MARK: - Briefing

    static func loadBriefing() -> AssistantBriefing? {
        guard let data = UserDefaults.standard.data(forKey: briefingDataKey) else { return nil }
        return try? JSONDecoder().decode(AssistantBriefing.self, from: data)
    }

    static func saveBriefing(_ briefing: AssistantBriefing) {
        guard let data = try? JSONEncoder().encode(briefing) else { return }
        UserDefaults.standard.set(data, forKey: briefingDataKey)
        UserDefaults.standard.set(Date(), forKey: briefingTimestampKey)
    }

    static func isBriefingStale() -> Bool {
        guard let savedDate = UserDefaults.standard.object(forKey: briefingTimestampKey) as? Date else {
            return true
        }
        return Date().timeIntervalSince(savedDate) > maxAge
    }

    // MARK: - Nudges

    static func loadNudges() -> [MailAssistantNudge]? {
        guard let data = UserDefaults.standard.data(forKey: nudgesDataKey) else { return nil }
        return try? JSONDecoder().decode([MailAssistantNudge].self, from: data)
    }

    static func saveNudges(_ nudges: [MailAssistantNudge]) {
        guard let data = try? JSONEncoder().encode(nudges) else { return }
        UserDefaults.standard.set(data, forKey: nudgesDataKey)
        UserDefaults.standard.set(Date(), forKey: nudgesTimestampKey)
    }

    static func isNudgesStale() -> Bool {
        guard let savedDate = UserDefaults.standard.object(forKey: nudgesTimestampKey) as? Date else {
            return true
        }
        return Date().timeIntervalSince(savedDate) > maxAge
    }

    // MARK: - Sign-out

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: briefingDataKey)
        UserDefaults.standard.removeObject(forKey: briefingTimestampKey)
        UserDefaults.standard.removeObject(forKey: nudgesDataKey)
        UserDefaults.standard.removeObject(forKey: nudgesTimestampKey)
    }
}
