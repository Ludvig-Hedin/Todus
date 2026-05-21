import Foundation

enum TaskViewMode: String, CaseIterable, Identifiable, Sendable {
    case list
    case board
    case table
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list:     return "List"
        case .board:    return "Board"
        case .table:    return "Table"
        case .calendar: return "Dates"
        }
    }

    var shortTitle: String { title }

    var systemImage: String {
        switch self {
        case .list:     return "list.bullet"
        case .board:    return "square.grid.2x2"
        case .table:    return "tablecells"
        case .calendar: return "calendar"
        }
    }
}
