import Foundation
import UserNotifications

/// Manages local notifications for task due dates.
///
/// **Action identifiers** (`Action.complete` / `Action.snooze`) must stay in sync with
/// `UNNotificationAction` registration below and with `AppDelegate` in `TodosApp.swift`.
@MainActor
@Observable
final class NotificationService {
    private(set) var isAuthorized = false

    private let center = UNUserNotificationCenter.current()

    private enum Category {
        static let taskReminder = "TASK_REMINDER"
    }

    /// Handled in `TodosApp` (`AppDelegate`); values are the `UNNotificationAction.identifier`s.
    enum Action {
        static let complete = "TASK_COMPLETE"
        static let snooze = "TASK_SNOOZE"
    }

    init() {
        registerCategories()
        Task { await checkAuthorization() }
    }

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await checkAuthorization()
            return granted
        } catch {
            return false
        }
    }

    /// Previous Resources implementation used this name; kept for call-site compatibility.
    func requestAuthorization() async -> Bool {
        await requestPermission()
    }

    func checkAuthorization() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            isAuthorized = true
        default:
            isAuthorized = false
        }
    }

    // MARK: - Task Reminders

    /// Schedule a local notification 1 hour before a task's due date.
    /// Silently no-ops if the date is in the past or notifications are denied.
    func scheduleTaskReminder(taskID: String, title: String, dueDate: Date) {
        Task { @MainActor in
            await scheduleTaskReminderAsync(taskID: taskID, title: title, dueDate: dueDate)
        }
    }

    private func scheduleTaskReminderAsync(taskID: String, title: String, dueDate: Date) async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = await requestPermission()
            guard granted else { return }
        case .authorized, .provisional, .ephemeral:
            break
        case .denied:
            return
        @unknown default:
            return
        }

        await checkAuthorization()

        let reminderDate = dueDate.addingTimeInterval(-3600)
        enqueueTaskReminder(taskID: taskID, title: title, fireDate: reminderDate)
    }

    private func enqueueTaskReminder(taskID: String, title: String, fireDate: Date) {
        guard isAuthorized else { return }
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Task Due Soon"
        content.body = title
        content.sound = .default
        content.categoryIdentifier = Category.taskReminder
        content.userInfo = ["taskID": taskID]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: "task-\(taskID)",
            content: content,
            trigger: trigger
        )

        center.add(request)
    }

    func cancelTaskReminder(taskID: String) {
        center.removePendingNotificationRequests(withIdentifiers: ["task-\(taskID)"])
    }

    /// Reschedule a task reminder 1 hour from now (used by the "Snooze" action).
    func snoozeTaskReminder(taskID: String, title: String) {
        let fireDate = Date().addingTimeInterval(3600)
        enqueueTaskReminder(taskID: taskID, title: title, fireDate: fireDate)
    }

    // MARK: - Utilities

    func clearAll() {
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
    }

    func cancel(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    // MARK: - Categories

    private func registerCategories() {
        let completeAction = UNNotificationAction(
            identifier: Action.complete,
            title: "Complete",
            options: [.destructive]
        )
        let snoozeAction = UNNotificationAction(
            identifier: Action.snooze,
            title: "Snooze 1h",
            options: []
        )

        let taskCategory = UNNotificationCategory(
            identifier: Category.taskReminder,
            actions: [completeAction, snoozeAction],
            intentIdentifiers: []
        )

        center.setNotificationCategories([taskCategory])
    }
}
