import Foundation

enum TaskViewMode: String, CaseIterable, Identifiable, Sendable {
    case list
    case board
    case table

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: return "List"
        case .board: return "Board"
        case .table: return "Table"
        }
    }

    var shortTitle: String { title }

    var systemImage: String {
        switch self {
        case .list: return "list.bullet"
        case .board: return "square.grid.2x2"
        case .table: return "tablecells"
        }
    }
}
