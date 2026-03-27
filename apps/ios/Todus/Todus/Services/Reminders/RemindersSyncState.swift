import Foundation

@MainActor
final class RemindersSyncState {
    var isEnabled: Bool = false
    var direction: RemindersSyncDirection = .twoWay
}
