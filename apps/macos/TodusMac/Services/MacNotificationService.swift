import Foundation
import UserNotifications

/// Local notification manager for the macOS app.
/// Uses the same `UserNotifications` framework as iOS and mirrors the iOS `NotificationService` API
/// so the two platforms stay in sync without sharing code across targets.
@MainActor
@Observable
final class MacNotificationService {
    private(set) var isAuthorized = false

    private let center = UNUserNotificationCenter.current()

    /// Notification category identifiers. Mirrors iOS `NotificationService.Category` so
    /// the same payloads route identically on both platforms. `AppDelegate`-style
    /// routing in `TodusMacApp` reads `categoryIdentifier` to decide where to send the user.
    enum Category {
        static let taskReminder = "TASK_REMINDER"
        static let emailNotification = "EMAIL_NOTIFICATION"
        static let emailReminder = "EMAIL_REMINDER"
        static let aiResponse = "AI_RESPONSE"
        static let dueTasks = "DUE_TASKS"
    }

    /// Action identifiers (must stay in sync with `UNNotificationAction` registration
    /// below and with the delegate routing in `TodusMacApp`).
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

    func checkAuthorization() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            isAuthorized = true
        default:
            isAuthorized = false
        }
    }

    // MARK: - Task Reminders

    /// Schedule a notification 1 hour before a task's due date.
    func scheduleTaskReminder(taskID: String, title: String, dueDate: Date) {
        let reminderDate = dueDate.addingTimeInterval(-3600)
        guard reminderDate > Date(), isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Task Due Soon"
        content.body = title
        content.sound = .default
        content.categoryIdentifier = Category.taskReminder
        content.userInfo = ["taskID": taskID]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminderDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "task-\(taskID)", content: content, trigger: trigger)
        center.add(request) { error in
            if let error { AppLogger.shared.log("[Notifications] add failed: \(error.localizedDescription)") }
        }
    }

    func cancelTaskReminder(taskID: String) {
        center.removePendingNotificationRequests(withIdentifiers: ["task-\(taskID)"])
    }

    // MARK: - Email Notifications

    /// Show a notification for a newly received email thread.
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
        center.add(request) { error in
            if let error { AppLogger.shared.log("[Notifications] add failed: \(error.localizedDescription)") }
        }
    }

    /// Schedule a reminder to revisit an email thread at a future date.
    /// Replaces any existing reminder for the same thread (so re-scheduling
    /// the same `threadId` cleanly updates the fire time). Mirrors iOS
    /// `NotificationService.scheduleEmailReminder`.
    @discardableResult
    func scheduleEmailReminder(threadId: String, subject: String, at fireDate: Date) async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = await requestPermission()
            guard granted else { return false }
        case .authorized, .provisional:
            break
        case .denied:
            return false
        @unknown default:
            return false
        }

        await checkAuthorization()
        guard isAuthorized else { return false }
        guard fireDate > Date() else { return false }

        let content = UNMutableNotificationContent()
        content.title = "Email reminder"
        content.body = subject.isEmpty ? "Return to this thread" : subject
        content.sound = .default
        content.categoryIdentifier = Category.emailReminder
        content.userInfo = ["threadId": threadId]
        content.threadIdentifier = "email-reminders"

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
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

    func scheduleDueTodayDigest(count: Int, titles: [String]) {
        guard isAuthorized, count > 0 else { return }

        let body: String
        if count == 1 {
            body = titles.first ?? "1 task due today"
        } else {
            let preview = titles.prefix(2).filter { !$0.isEmpty }.joined(separator: ", ")
            if preview.isEmpty {
                body = "\(count) tasks due today"
            } else {
                body = "\(count) tasks due today — \(preview)\(count > 2 ? "…" : "")"
            }
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
        center.add(request) { error in
            if let error { AppLogger.shared.log("[Notifications] add failed: \(error.localizedDescription)") }
        }
    }

    // MARK: - AI Response Notifications

    /// Convenience overload matching the iOS `snippet:` label naming used at some
    /// call sites; forwards to the canonical `preview:` implementation.
    func scheduleAIResponseNotification(conversationId: String, snippet: String) {
        scheduleAIResponseNotification(conversationId: conversationId, preview: snippet)
    }

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
        center.add(request) { error in
            if let error { AppLogger.shared.log("[Notifications] add failed: \(error.localizedDescription)") }
        }
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
