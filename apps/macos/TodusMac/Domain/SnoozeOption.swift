import Foundation

/// Shared snooze presets used by macOS task row context-menu and detail
/// panel. Mirrors the iOS `SnoozeOption` so both platforms agree on what
/// "Tomorrow morning" means.
enum SnoozeOption: CaseIterable {
    case tonight
    case tomorrow
    case weekend
    case nextWeek

    var label: String {
        switch self {
        case .tonight: return "Tonight (8 pm)"
        case .tomorrow: return "Tomorrow morning"
        case .weekend: return "This weekend"
        case .nextWeek: return "Next week"
        }
    }

    func date(now: Date = .now, calendar: Calendar = .current) -> Date {
        switch self {
        case .tonight:
            let candidate = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now)
                ?? now.addingTimeInterval(4 * 3600)
            if candidate <= now {
                return calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            }
            return candidate
        case .tomorrow:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)
                ?? now.addingTimeInterval(86_400)
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        case .weekend:
            let weekday = calendar.component(.weekday, from: now) // Sunday = 1, Saturday = 7
            let daysUntilSaturday = ((7 - weekday) + 7) % 7
            let target = daysUntilSaturday == 0 ? 7 : daysUntilSaturday
            let saturday = calendar.date(byAdding: .day, value: target, to: now)
                ?? now.addingTimeInterval(Double(target) * 86_400)
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: saturday) ?? saturday
        case .nextWeek:
            let nextWeek = calendar.date(byAdding: .day, value: 7, to: now)
                ?? now.addingTimeInterval(7 * 86_400)
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nextWeek) ?? nextWeek
        }
    }
}
