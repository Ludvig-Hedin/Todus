import Foundation

/// The type of item to create from the universal Create sheet.
/// "Auto" lets AI decide based on the text input.
enum CreateItemType: String, CaseIterable, Identifiable {
    case auto
    case task
    case event
    case email

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:  return "Auto"
        case .task:  return "Task"
        case .event: return "Event"
        case .email: return "Email"
        }
    }

    var icon: String {
        switch self {
        case .auto:  return "wand.and.stars"
        case .task:  return "checklist"
        case .event: return "calendar.badge.plus"
        case .email: return "envelope"
        }
    }
}
