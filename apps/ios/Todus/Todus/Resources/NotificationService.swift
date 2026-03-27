import Foundation
import UserNotifications

/// Handles local notification permissions and scheduling.
///
/// Current usage: AppServices holds a single instance. This service
/// is intentionally minimal so the app compiles; you can extend it to
/// schedule task and calendar reminders as needed.
@MainActor
final class NotificationService {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        // Optionally perform a lightweight authorization check on init
        // so we can prompt at first use later.
        center.getNotificationSettings { _ in }
    }

    /// Requests alert/badge/sound authorization from the user.
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    /// Clears all delivered notifications and pending requests.
    func clearAll() {
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
    }

    /// Cancels any pending notifications matching the provided identifiers.
    func cancel(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    // MARK: - Scheduling Stubs

    /// Schedules a simple one-off notification at a specific date.
    /// Returns the generated request identifier if successfully enqueued.
    @discardableResult
    func schedule(title: String, body: String, at date: Date, id: String = UUID().uuidString) -> String? {
        // Build trigger
        let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)

        // Content
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // Request
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request) { error in
            #if DEBUG
            if let error { print("Notification scheduling error: \(error)") }
            #endif
        }
        return id
    }
}
