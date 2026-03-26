import Foundation

enum TaskStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case todo
    case doing
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo:
            return "Todo"
        case .doing:
            return "Doing"
        case .done:
            return "Done"
        }
    }
}
