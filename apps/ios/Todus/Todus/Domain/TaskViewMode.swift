import Foundation

enum TaskViewMode: String, CaseIterable, Identifiable, Sendable {
    case list
    case board
    case table
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: return "List"
        case .board: return "Board"
        case .table: return "Table"
        case .calendar: return "By Date"
        }
    }

    var shortTitle: String {
        switch self {
        case .list: return "List"
        case .board: return "Board"
        case .table: return "Table"
        case .calendar: return "Dates"
        }
    }

    var systemImage: String {
        switch self {
        case .list: return "list.bullet"
        case .board: return "rectangle.split.3x1"
        case .table: return "tablecells"
        case .calendar: return "calendar"
        }
    }
}
