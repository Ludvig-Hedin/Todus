import EventKit
import Foundation
import OSLog
import SwiftData

private let startupLog = Logger(subsystem: "com.todus.startup", category: "reminders")

// MARK: - Value Types

/// Sendable snapshot of an EKReminder's data — safe to pass across actor boundaries
/// because EKReminder itself is not Sendable (reference type from ObjC framework).
struct ImportedReminder: Sendable {
    let identifier: String
    let title: String
    let notes: String
    let dueDate: Date?
}

// MARK: - Background Storage Actor

/// Owns EKEventStore and performs all reminder I/O off the main thread.
///
/// EKEventStore.save/remove/calendarItem are synchronous XPC calls to the Reminders
/// daemon. Running them on the main actor causes "Fence Hang" watchdog violations
/// (9000+ ms freezes visible in the iOS performance HUD). By isolating all EKEventStore
/// work to this background actor, the main thread is only *suspended* (not *blocked*)
/// during await calls — keeping the UI fully responsive.
private actor RemindersStorageActor {
    // MUST be lazy — actor designated inits run on the CALLING context (main thread),
    // not on the actor's background executor. If this were `let`, EKEventStore() would
    // be created synchronously on the main thread during AppServices.init(), causing the
    // "Fence Hang / 9000ms black screen on startup" watchdog violation.
    // With `lazy var`, the store is created on first method call, which happens on the
    // actor's background executor (off the main thread).
    private lazy var store = EKEventStore()

    func requestFullAccess() async throws -> Bool {
        startupLog.info("⏱ RemindersStorageActor: requestFullAccess — EKEventStore first touch here if lazy")
        return try await store.requestFullAccessToReminders()
    }

    /// Creates or updates a reminder. Returns the calendarItemIdentifier on success.
    func save(
        title: String,
        notes: String,
        priority: Int,
        isCompleted: Bool,
        completionDate: Date?,
        dueDate: Date?,
        existingIdentifier: String?
    ) throws -> String {
        // Reuse existing reminder if we have a valid identifier, otherwise create a new one.
        let reminder = existingIdentifier.flatMap {
            store.calendarItem(withIdentifier: $0) as? EKReminder
        } ?? EKReminder(eventStore: store)

        reminder.title = title
        reminder.notes = notes
        reminder.priority = priority
        reminder.isCompleted = isCompleted
        reminder.completionDate = completionDate

        let calendars = store.calendars(for: .reminder)
        reminder.calendar = calendars.first(where: { $0.allowsContentModifications }) ?? calendars.first

        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: dueDate
            )
        } else {
            reminder.dueDateComponents = nil
        }

        // commit:true — each save is independent; acceptable for single-task mutations.
        // syncAllTasks fires multiple Tasks, all queued on this actor, so they serialize
        // automatically without needing a manual batched commit.
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    func delete(identifier: String) throws {
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return }
        try store.remove(reminder, commit: true)
    }

    /// Fetches all incomplete reminders from all lists and converts them to Sendable
    /// value types before returning — EKReminder is not Sendable so all data extraction
    /// happens here on the actor, safe to pass the result back to the main actor.
    func fetchAllIncompleteReminders() async -> [ImportedReminder] {
        let predicate = store.predicateForReminders(in: nil) // nil = search all lists
        let imported: [ImportedReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let results: [ImportedReminder] = (reminders ?? []).filter { !$0.isCompleted }.map { reminder in
                    let dueDate: Date? = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
                    return ImportedReminder(
                        identifier: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "",
                        notes: reminder.notes ?? "",
                        dueDate: dueDate
                    )
                }
                continuation.resume(returning: results)
            }
        }
        return imported
    }
}

// MARK: - Service

@MainActor
final class AppleRemindersSyncService {
    // Log when this service is created to verify it's fast (no EKEventStore init here).
    init() {
        startupLog.info("⏱ AppleRemindersSyncService.init() — EKEventStore NOT created yet (lazy)")
    }
    enum AuthorizationState: String {
        case notDetermined
        case restricted
        case denied
        case authorized
    }

    // Single shared actor instance — its serial queue serializes all EKEventStore I/O.
    private let storage = RemindersStorageActor()

    func authorizationState() -> AuthorizationState {
        // authorizationStatus is a class method and doesn't block — safe to call on main.
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized, .fullAccess, .writeOnly: return .authorized
        @unknown default: return .denied
        }
    }

    func requestAccess() async -> Bool {
        do {
            return try await storage.requestFullAccess()
        } catch {
            return false
        }
    }

    /// Saves a reminder asynchronously. EKEventStore XPC work runs on RemindersStorageActor
    /// (off the main thread). The main actor is suspended — not blocked — during the await,
    /// so the UI stays responsive even when many tasks are being synced.
    func upsert(_ task: TaskRecord, in context: ModelContext) {
        guard authorizationState() == .authorized else { return }

        // Capture only Sendable (value-type) data from the task before leaving the main actor.
        let title = task.title
        let notes = task.taskDescription.isEmpty ? task.rawInput : task.taskDescription
        let priority = task.priority.reminderPriority
        let isCompleted = task.completed
        let completionDate = task.completed ? task.updatedAt : nil
        let dueDate = task.dueDate
        let existingIdentifier = task.reminderIdentifier
        let taskID = task.id

        // Task { } inherits @MainActor isolation; the `await storage.save(...)` suspends
        // this task (freeing the main thread) while the storage actor does the XPC work.
        // After the await, execution resumes on the main actor to update SwiftData safely.
        Task {
            guard let identifier = try? await storage.save(
                title: title,
                notes: notes,
                priority: priority,
                isCompleted: isCompleted,
                completionDate: completionDate,
                dueDate: dueDate,
                existingIdentifier: existingIdentifier
            ) else { return }

            // Back on the main actor — safe to use the SwiftData ModelContext.
            let descriptor = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == taskID })
            guard let task = try? context.fetch(descriptor).first else { return }
            task.reminderIdentifier = identifier
            task.syncState = .pendingUpload
            try? context.save()
        }
    }

    func delete(_ task: TaskRecord) {
        guard authorizationState() == .authorized else { return }
        guard let identifier = task.reminderIdentifier else { return }

        Task {
            try? await storage.delete(identifier: identifier)
        }
    }

    /// Syncs all tasks to Reminders. Each upsert fires an async Task that queues on the
    /// storage actor — they run serially off the main thread, so the UI is never blocked.
    func syncAllTasks(_ tasks: [TaskRecord], in context: ModelContext) {
        guard authorizationState() == .authorized else { return }
        for task in tasks {
            upsert(task, in: context)
        }
    }

    /// Imports incomplete Apple Reminders that aren't already tracked in the app.
    /// Skips any reminder whose calendarItemIdentifier already exists on a TaskRecord
    /// to prevent duplicating tasks on repeated calls.
    func importFromReminders(in context: ModelContext) async {
        guard authorizationState() == .authorized else { return }

        // Fetch incomplete reminders on the background actor (off main thread)
        let reminders = await storage.fetchAllIncompleteReminders()

        // Build a set of identifiers already linked to app tasks — avoids duplicates
        let descriptor = FetchDescriptor<TaskRecord>()
        let existingTasks = (try? context.fetch(descriptor)) ?? []
        let trackedIdentifiers = Set(existingTasks.compactMap(\.reminderIdentifier))

        var didInsert = false
        for reminder in reminders {
            guard !trackedIdentifiers.contains(reminder.identifier) else { continue }
            guard !reminder.title.isEmpty else { continue }

            // Mark as `parsed` (title already set — no AI enrichment needed) and
            // `synced` (originated in Reminders, nothing to push back right now).
            let task = TaskRecord(
                rawInput: reminder.title,
                title: reminder.title,
                taskDescription: reminder.notes,
                reminderIdentifier: reminder.identifier,
                dueDate: reminder.dueDate,
                parseState: .parsed,
                syncState: .synced
            )
            context.insert(task)
            didInsert = true
        }

        if didInsert {
            try? context.save()
            AppLogger.shared.log("importFromReminders: inserted \(reminders.count) reminder(s) as tasks")
        }
    }
}

// MARK: - Priority Mapping

private extension AppTaskPriority {
    var reminderPriority: Int {
        switch self {
        case .none: return 0
        case .low: return 1
        case .medium: return 5
        case .high: return 9
        }
    }
}
