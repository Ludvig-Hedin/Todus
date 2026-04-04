import SwiftUI

/// All navigation destinations in Todus. Some live in the tab bar, others on the Home dashboard.
enum AppTab: String, CaseIterable, Identifiable, Hashable, Codable {
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

    /// One-line description shown in tab bar customization UI.
    var description: String {
        switch self {
        case .home:     return "Your daily overview"
        case .tasks:    return "Capture and manage tasks"
        case .email:    return "Gmail inbox and threads"
        case .calendar: return "Events and schedule"
        case .meetings: return "Recorded meetings & AI summaries"
        }
    }

    /// Home tab is always present — it's the anchor for pages not in the tab bar.
    var isRequired: Bool { self == .home }

    /// Tabs shown in the tab bar by default (first launch).
    /// Max 4 — the burger (More) button adds a fixed 5th visual slot so the pill isn't cramped.
    /// Meetings is accessible via the More sheet and the Home "More" section by default.
    static let defaultNavTabs: [AppTab] = [.home, .tasks, .email, .calendar]

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
