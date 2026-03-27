import Foundation

/// Direction for Apple Reminders synchronization.
/// 
/// - twoWay: Keep app tasks and Apple Reminders in sync in both directions.
/// - toReminders: Only push changes from the app to Apple Reminders.
/// - fromReminders: Only import changes from Apple Reminders into the app.
enum RemindersSyncDirection: String, CaseIterable, Identifiable, Sendable {
    case twoWay
    case toReminders
    case fromReminders

    var id: String { rawValue }

    /// A short human-readable label suitable for settings UI.
    var title: String {
        switch self {
        case .twoWay: return "Two-way"
        case .toReminders: return "App → Reminders"
        case .fromReminders: return "Reminders → App"
        }
    }
}
