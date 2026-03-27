import Foundation
import UserNotifications

/// Manages local notifications for task due dates and calendar events.
/// Wraps UNUserNotificationCenter with category registration and scheduling helpers.
@MainActor
@Observable
final class NotificationService {
    private(set) var isAuthorized = false

    private let center = UNUserNotificationCenter.current()

    // Notification category identifiers
    private enum Category {
        static let taskReminder = "TASK_REMINDER"
    }

    // Action identifiers — handled in TodosApp.swift
    enum Action {
        static let complete = "TASK_COMPLETE"
        static let snooze = "TASK_SNOOZE"
    }

    init() {
        registerCategories()
        Task { await checkAuthorization() }
    }

    // MARK: - Permission

    /// Request notification permission. Returns true if granted.
    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            return granted
        } catch {
            return false
        }
    }

    /// Check current authorization status without prompting.
    func checkAuthorization() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Task Reminders

    /// Schedule a local notification 1 hour before a task's due date.
    /// Silently no-ops if the task has no due date or the date is in the past.
    func scheduleTaskReminder(taskID: String, title: String, dueDate: Date) {
        // Remind 1 hour before the due instant.
        let reminderDate = dueDate.addingTimeInterval(-3600)
        enqueueTaskReminder(taskID: taskID, title: title, fireDate: reminderDate)
    }

    /// Enqueues the standard task reminder notification at an absolute fire date.
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

    /// Cancel a previously scheduled task reminder.
    func cancelTaskReminder(taskID: String) {
        center.removePendingNotificationRequests(withIdentifiers: ["task-\(taskID)"])
    }

    /// Reschedule a task reminder 1 hour from now (used by the "Snooze" action).
    /// Schedules at an absolute fire time instead of a synthetic `dueDate` — clearer than
    /// `scheduleTaskReminder(dueDate: now + 2h)`, which was equivalent but easy to misread.
    func snoozeTaskReminder(taskID: String, title: String) {
        let fireDate = Date().addingTimeInterval(3600)
        enqueueTaskReminder(taskID: taskID, title: title, fireDate: fireDate)
    }

    // MARK: - Private

    /// Register notification categories with action buttons.
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
