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
            // Nearest UPCOMING weekend day (Saturday OR Sunday) still in the future, at 9am.
            // (B-033.) Invoked Saturday afternoon → this Sunday 9am (not next Saturday);
            // Sunday before 9am → this Sunday; Sunday after 9am → next Saturday.
            return Self.nextWeekendMorning(now: now, calendar: calendar)
        case .nextWeek:
            let nextWeek = calendar.date(byAdding: .day, value: 7, to: now)
                ?? now.addingTimeInterval(7 * 86_400)
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nextWeek) ?? nextWeek
        }
    }

    /// Returns the nearest upcoming weekend morning (Saturday or Sunday at 9am) that is
    /// strictly in the future. If neither this week's Saturday nor Sunday 9am is still
    /// ahead (e.g. late Sunday), rolls forward to next Saturday. (B-033.)
    /// Kept in sync with the iOS mirror in `Todus/Features/Tasks/TaskRowView.swift`.
    static func nextWeekendMorning(now: Date, calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: now) // Sunday = 1, Saturday = 7
        let daysUntilSaturday = ((7 - weekday) + 7) % 7       // 0 when today is Saturday
        let daysUntilSunday = ((1 - weekday) + 7) % 7         // 0 when today is Sunday

        func morning(daysAhead: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: daysAhead, to: now)
                ?? now.addingTimeInterval(Double(daysAhead) * 86_400)
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        }

        let candidates = [morning(daysAhead: daysUntilSaturday), morning(daysAhead: daysUntilSunday)]
        if let soonest = candidates.filter({ $0 > now }).min() {
            return soonest
        }
        // Both this-week candidates have passed (late Sunday) → next Saturday 9am.
        return morning(daysAhead: daysUntilSaturday + 7)
    }
}
