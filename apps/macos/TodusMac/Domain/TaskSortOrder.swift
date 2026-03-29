import Foundation

/// Sort order options for the task list view.
enum TaskSortOrder: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case alphabetical
    case dueDate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: return "Newest First"
        case .oldest: return "Oldest First"
        case .alphabetical: return "Alphabetical"
        case .dueDate: return "Due Date"
        }
    }

    var systemImage: String {
        switch self {
        case .newest: return "arrow.down.circle"
        case .oldest: return "arrow.up.circle"
        case .alphabetical: return "textformat.abc"
        case .dueDate: return "calendar"
        }
    }
}
