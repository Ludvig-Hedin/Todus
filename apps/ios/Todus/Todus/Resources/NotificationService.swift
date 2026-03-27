import Foundation
import UserNotifications

/// Handles local notification permissions and scheduling.
///
/// Current usage: AppServices holds a single instance. This service
/// is intentionally minimal so the app compiles; you can extend it to
/// schedule task and calendar reminders as needed.
@MainActor
final class NotificationService {
    enum Action {
        static let complete = "complete"
        static let snooze = "snooze"
    }

    enum Category {
        static let taskReminder = "taskReminder"
    }
    
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        // Optionally perform a lightweight authorization check on init
        // so we can prompt at first use later.
        center.getNotificationSettings { _ in }

        // Register actionable notification category for task reminders
        let complete = UNNotificationAction(
            identifier: Action.complete,
            title: "Complete",
            options: [.authenticationRequired]
        )
        let snooze = UNNotificationAction(
            identifier: Action.snooze,
            title: "Snooze 1h",
            options: []
        )
        let taskCategory = UNNotificationCategory(
            identifier: Category.taskReminder,
            actions: [complete, snooze],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([taskCategory])
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
        // Attach category and task ID so actions work and the app can resolve the task
        content.categoryIdentifier = Category.taskReminder
        content.userInfo = ["taskID": id]

        // Request
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request) { error in
            #if DEBUG
            if let error { print("Notification scheduling error: \(error)") }
            #endif
        }
        return id
    }

    /// Convenience: schedule a task due reminder using task ID as the notification identifier.
    /// Checks authorization status and requests permission if needed before scheduling.
    func scheduleTaskReminder(taskID: String, title: String, dueDate: Date) {
        // Fire-and-forget async wrapper so callers don't need to await
        Task { @MainActor in
            await scheduleTaskReminderAsync(taskID: taskID, title: title, dueDate: dueDate)
        }
    }

    /// Async implementation: checks/requests authorization before scheduling the notification.
    private func scheduleTaskReminderAsync(taskID: String, title: String, dueDate: Date) async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = await requestAuthorization()
            guard granted else { return }
        case .authorized, .provisional, .ephemeral:
            break
        case .denied:
            return
        @unknown default:
            return
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let body = "Due \(formatter.string(from: dueDate))"
        _ = schedule(title: title, body: body, at: dueDate, id: taskID)
    }

    /// Convenience: cancel a previously scheduled task reminder by task ID.
    func cancelTaskReminder(taskID: String) {
        cancel(withIdentifiers: [taskID])
    }
}
