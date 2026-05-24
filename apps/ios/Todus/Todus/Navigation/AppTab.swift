import SwiftUI

/// All navigation destinations in Todus. Some live in the tab bar, others on the Home dashboard.
enum AppTab: String, CaseIterable, Identifiable, Hashable, Codable {
    case home
    case tasks
    case email
    case calendar
    case meetings
    case docs
    /// Action-only tab — tapping it opens the create sheet; never becomes a real navigation destination.
    case create
    /// AI/search tab — pinned to the trailing side via `Tab(role: .search)`.
    case ai

    var id: String { rawValue }

    /// Human-readable label (accessibility; not shown in icon-only mode).
    var title: String {
        switch self {
        case .home:     return "Home"
        case .tasks:    return "Tasks"
        case .email:    return "Email"
        case .calendar: return "Calendar"
        case .meetings: return "Meetings"
        case .docs:     return "Docs"
        case .create:   return "New"
        case .ai:       return "AI"
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
        case .docs:     return "Documents and notes"
        case .create:   return "Create a new item"
        case .ai:       return "AI assistant"
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
        case .docs:     return "doc.text.fill"
        case .create:   return "plus.circle.fill"
        case .ai:       return "sparkles"
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
        case .docs:     return "doc.text"
        case .create:   return "plus.circle.fill"
        case .ai:       return "sparkles"
        }
    }

    /// iOS 17 legacy .tabItem icon — system applies tint for selection.
    var legacyIcon: String { inactiveIcon() }
}
