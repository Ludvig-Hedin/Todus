import SwiftUI

/// The four primary navigation tabs in the unified Todus app.
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case tasks
    case email
    case calendar
    case meetings

    var id: String { rawValue }

    /// Human-readable label (accessibility; not shown in icon-only mode).
    var title: String {
        switch self {
        case .home:     return "Home"
        case .tasks:    return "Tasks"
        case .email:    return "Email"
        case .calendar: return "Calendar"
        case .meetings: return "Meetings"
        }
    }

    /// SF Symbol shown when this tab is selected.
    var activeIcon: String {
        switch self {
        case .home:     return "house.fill"
        case .tasks:    return "checklist"
        case .email:    return "envelope.fill"
        case .calendar: return "calendar.badge.plus"
        case .meetings: return "video.fill"
        }
    }

    /// SF Symbol shown when this tab is inactive.
    /// Pass hasEvent = true for the calendar event-badge variant.
    func inactiveIcon(hasEvent: Bool = false) -> String {
        switch self {
        case .home:     return "house"
        case .tasks:    return "checklist"
        case .email:    return "envelope"
        case .calendar: return hasEvent ? "calendar.badge" : "calendar"
        case .meetings: return "video"
        }
    }

    /// iOS 17 legacy .tabItem icon — system applies tint for selection.
    var legacyIcon: String { inactiveIcon() }
}
