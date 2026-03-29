import Foundation
import SwiftUI

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

    /// Subtle column accent — used for add-task button borders, header dots, and drop highlights
    var tintColor: Color {
        switch self {
        case .todo:
            return Color(red: 0.55, green: 0.55, blue: 0.60)   // neutral slate
        case .doing:
            return Color(red: 0.40, green: 0.56, blue: 0.85)   // calm blue
        case .done:
            return Color(red: 0.38, green: 0.72, blue: 0.50)   // soft green
        }
    }

    /// Icon for column header
    var systemImage: String {
        switch self {
        case .todo:  return "circle"
        case .doing: return "circle.lefthalf.filled"
        case .done:  return "checkmark.circle.fill"
        }
    }
}
