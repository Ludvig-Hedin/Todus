import Foundation

/// Urgency-aware sort used by the `Smart` sort order.
///
/// Bucket order (lower = earlier):
///   1. Overdue           — anything with a due-date in the past, oldest-overdue first
///   2. Due today
///   3. Future due-date   — soonest first
///   4. No due-date, high priority
///   5. No due-date       — by recency (newest first)
enum TaskSmartSort {
    /// Visible bucket the smart sort exposes to the UI. macOS list view
    /// renders one section per non-empty bucket so the user sees structure.
    enum Bucket: Int, CaseIterable, Identifiable {
        case overdue
        case today
        case thisWeek
        case later
        case noDate

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .overdue: return "Overdue"
            case .today: return "Today"
            case .thisWeek: return "This week"
            case .later: return "Later"
            case .noDate: return "No date"
            }
        }

        var subtitle: String {
            switch self {
            case .overdue: return "Was due before today"
            case .today: return "Needs attention now"
            case .thisWeek: return "Coming up in the next 7 days"
            case .later: return "Further out"
            case .noDate: return "Nothing scheduled yet"
            }
        }

        var systemImage: String {
            switch self {
            case .overdue: return "exclamationmark.circle.fill"
            case .today: return "sun.max.fill"
            case .thisWeek: return "calendar"
            case .later: return "calendar.badge.clock"
            case .noDate: return "tray"
            }
        }
    }

    static func bucketed(_ tasks: [TaskRecord], now: Date = .now) -> [(bucket: Bucket, tasks: [TaskRecord])] {
        let cal = Calendar.current
        let sorted = sorted(tasks, now: now, calendar: cal)
        let weekHorizon = cal.date(byAdding: .day, value: 7, to: now) ?? now.addingTimeInterval(7 * 86_400)

        var groups: [Bucket: [TaskRecord]] = [:]
        for task in sorted {
            let bucket = bucket(for: task, now: now, weekHorizon: weekHorizon, calendar: cal)
            groups[bucket, default: []].append(task)
        }
        return Bucket.allCases.compactMap { b in
            guard let tasks = groups[b], !tasks.isEmpty else { return nil }
            return (b, tasks)
        }
    }

    private static func bucket(for task: TaskRecord, now: Date, weekHorizon: Date, calendar: Calendar) -> Bucket {
        guard let due = task.dueDate else { return .noDate }
        if calendar.isDateInToday(due) { return .today }
        if due < now { return .overdue }
        if due < weekHorizon { return .thisWeek }
        return .later
    }

    static func sorted(_ tasks: [TaskRecord]) -> [TaskRecord] {
        sorted(tasks, now: .now, calendar: .current)
    }

    private static func sorted(_ tasks: [TaskRecord], now: Date, calendar: Calendar) -> [TaskRecord] {
        return tasks.sorted { lhs, rhs in
            let l = score(for: lhs, now: now, calendar: calendar)
            let r = score(for: rhs, now: now, calendar: calendar)
            if l.bucket != r.bucket { return l.bucket < r.bucket }
            if l.dateKey != r.dateKey { return l.dateKey < r.dateKey }
            if l.priorityRank != r.priorityRank { return l.priorityRank < r.priorityRank }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private struct Score {
        let bucket: Int
        let dateKey: TimeInterval
        let priorityRank: Int
    }

    private static func score(for task: TaskRecord, now: Date, calendar: Calendar) -> Score {
        let priorityRank: Int = {
            switch task.priority {
            case .high: return 0
            case .medium: return 1
            case .low: return 2
            default: return 3
            }
        }()

        guard let due = task.dueDate else {
            if task.priority == .high {
                return Score(bucket: 3, dateKey: -task.createdAt.timeIntervalSinceReferenceDate, priorityRank: priorityRank)
            }
            return Score(bucket: 4, dateKey: -task.createdAt.timeIntervalSinceReferenceDate, priorityRank: priorityRank)
        }

        if due < now && !calendar.isDateInToday(due) {
            return Score(bucket: 0, dateKey: due.timeIntervalSinceReferenceDate, priorityRank: priorityRank)
        }

        if calendar.isDateInToday(due) {
            return Score(bucket: 1, dateKey: due.timeIntervalSinceReferenceDate, priorityRank: priorityRank)
        }

        return Score(bucket: 2, dateKey: due.timeIntervalSinceReferenceDate, priorityRank: priorityRank)
    }
}
