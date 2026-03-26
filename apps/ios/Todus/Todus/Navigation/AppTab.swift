import SwiftUI

/// The four primary tabs in the unified Todus app.
enum AppTab: String, CaseIterable, Identifiable {
    case home
    case tasks
    case email
    case calendar

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home:     return "house.fill"
        case .tasks:    return "checklist"
        case .email:    return "envelope.fill"
        case .calendar: return "calendar"
        }
    }
}
