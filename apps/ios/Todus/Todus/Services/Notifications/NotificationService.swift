import Foundation
import UIKit
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
        static let emailNotification = "EMAIL_NOTIFICATION"
        static let emailReminder = "EMAIL_REMINDER"
        static let aiResponse = "AI_RESPONSE"
        static let dueTasks = "DUE_TASKS"
    }

    /// Handled in `TodosApp` (`AppDelegate`); values are the `UNNotificationAction.identifier`s.
    enum Action {
        static let complete = "TASK_COMPLETE"
        static let snooze = "TASK_SNOOZE"
        static let archiveEmail = "EMAIL_ARCHIVE"
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

        // Always cancel the prior pending request for this task ID before scheduling.
        // `center.add` with the same identifier already replaces a pending request,
        // but a previously-fired (delivered) notification with the same identifier
        // is not auto-removed — explicit cancel keeps stale reminders out of the
        // tray when a user reschedules right around the original fire time.
        center.removePendingNotificationRequests(withIdentifiers: ["task-\(taskID)"])
        center.removeDeliveredNotifications(withIdentifiers: ["task-\(taskID)"])

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

    // MARK: - Email Notifications

    /// Show a local notification for a newly received email thread.
    func scheduleNewEmailNotification(threadId: String, from: String, subject: String) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = from
        content.body = subject.isEmpty ? "New message" : subject
        content.sound = .default
        content.categoryIdentifier = Category.emailNotification
        content.userInfo = ["threadId": threadId]
        content.threadIdentifier = "email-threads"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "email-\(threadId)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    /// Schedule a reminder for revisiting an email thread.
    /// Replaces any existing reminder for the same thread.
    func scheduleEmailReminder(threadId: String, from: String, subject: String, remindAt: Date) async -> Bool {
        await scheduleEmailReminderAsync(
            threadId: threadId,
            from: from,
            subject: subject,
            remindAt: remindAt
        )
    }

    private func scheduleEmailReminderAsync(
        threadId: String,
        from: String,
        subject: String,
        remindAt: Date
    ) async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = await requestPermission()
            guard granted else { return false }
        case .authorized, .provisional, .ephemeral:
            break
        case .denied:
            return false
        @unknown default:
            return false
        }

        await checkAuthorization()
        guard isAuthorized else { return false }
        guard remindAt > Date() else { return false }

        let content = UNMutableNotificationContent()
        content.title = from.isEmpty ? "Email reminder" : from
        content.body = subject.isEmpty ? "Return to this thread" : subject
        content.sound = .default
        content.categoryIdentifier = Category.emailReminder
        content.userInfo = ["threadId": threadId]
        content.threadIdentifier = "email-reminders"

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: remindAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: "email-reminder-\(threadId)",
            content: content,
            trigger: trigger
        )

        center.removePendingNotificationRequests(withIdentifiers: ["email-reminder-\(threadId)"])
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Due-Task Digest

    /// Show a notification summarising tasks due today.
    /// Replaces any pending digest so only the freshest count is shown.
    func scheduleDueTodayDigest(count: Int, titles: [String]) {
        guard isAuthorized else { return }
        if count == 0 {
            center.removePendingNotificationRequests(withIdentifiers: ["due-today-digest"])
            center.removeDeliveredNotifications(withIdentifiers: ["due-today-digest"])
            center.setBadgeCount(0)
            return
        }

        let body: String
        if count == 1 {
            body = titles.first ?? "1 task due today"
        } else {
            let preview = titles.prefix(2).joined(separator: ", ")
            body = "\(count) tasks due today — \(preview)\(count > 2 ? "…" : "")"
        }

        let content = UNMutableNotificationContent()
        content.title = "Tasks due today"
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Category.dueTasks
        content.badge = count as NSNumber

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "due-today-digest", content: content, trigger: trigger)
        center.removePendingNotificationRequests(withIdentifiers: ["due-today-digest"])
        center.add(request)
    }

    // MARK: - AI Response Notifications

    /// Show a notification when the AI replies (useful when the app is backgrounded mid-stream).
    func scheduleAIResponseNotification(conversationId: String, preview: String) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Todus AI"
        content.body = preview.isEmpty ? "Your AI reply is ready" : preview
        content.sound = .default
        content.categoryIdentifier = Category.aiResponse
        content.userInfo = ["conversationId": conversationId]
        content.threadIdentifier = "ai-responses"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "ai-\(conversationId)",
            content: content,
            trigger: trigger
        )
        center.removePendingNotificationRequests(withIdentifiers: ["ai-\(conversationId)"])
        center.add(request)
    }

    func cancelAIResponseNotification(conversationId: String) {
        center.removePendingNotificationRequests(withIdentifiers: ["ai-\(conversationId)"])
        center.removeDeliveredNotifications(withIdentifiers: ["ai-\(conversationId)"])
    }

    // MARK: - Utilities

    func clearAll() {
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
        // The due-today digest carries the app icon badge; clearing notifications
        // without resetting it leaves a stale due-count badge on the icon.
        center.setBadgeCount(0)
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
        let dueTasksCategory = UNNotificationCategory(
            identifier: Category.dueTasks,
            actions: [],
            intentIdentifiers: []
        )

        let archiveAction = UNNotificationAction(
            identifier: Action.archiveEmail,
            title: "Archive",
            options: [.destructive]
        )
        let emailCategory = UNNotificationCategory(
            identifier: Category.emailNotification,
            actions: [archiveAction],
            intentIdentifiers: []
        )
        let emailReminderCategory = UNNotificationCategory(
            identifier: Category.emailReminder,
            actions: [],
            intentIdentifiers: []
        )

        let aiCategory = UNNotificationCategory(
            identifier: Category.aiResponse,
            actions: [],
            intentIdentifiers: []
        )

        center.setNotificationCategories([
            taskCategory,
            dueTasksCategory,
            emailCategory,
            emailReminderCategory,
            aiCategory,
        ])
    }
}
