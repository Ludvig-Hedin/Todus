import Foundation

/// Sort order options for the task list view.
enum TaskSortOrder: String, CaseIterable, Identifiable {
    /// Urgency-aware default: overdue → today → upcoming → no-date.
    /// What a user opening Tasks usually wants — "what should I do next?".
    case smart
    case newest
    case oldest
    case alphabetical
    case dueDate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart: return "Smart"
        // Shortened from "Newest First" / "Oldest First" — the menu chip in
        // TasksTabView only has room for ~10 chars before truncating. Enum
        // case names stay `.newest` / `.oldest` to keep behaviour identical.
        // (UX P5.)
        case .newest: return "Recent"
        case .oldest: return "Oldest"
        case .alphabetical: return "Alphabetical"
        case .dueDate: return "Due Date"
        }
    }

    var systemImage: String {
        switch self {
        case .smart: return "sparkles"
        case .newest: return "arrow.down.circle"
        case .oldest: return "arrow.up.circle"
        case .alphabetical: return "textformat.abc"
        case .dueDate: return "calendar"
        }
    }
}
