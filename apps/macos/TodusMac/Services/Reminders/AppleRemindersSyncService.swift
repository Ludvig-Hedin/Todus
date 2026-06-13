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
private actor RemindersStorageActor {
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
        let reminder = existingIdentifier.flatMap {
            store.calendarItem(withIdentifier: $0) as? EKReminder
        } ?? EKReminder(eventStore: store)

        reminder.title = title
        reminder.notes = notes
        reminder.priority = priority
        reminder.isCompleted = isCompleted
        reminder.completionDate = completionDate

        let calendars = store.calendars(for: .reminder)
        guard let targetCalendar = calendars.first(where: { $0.allowsContentModifications }) ?? calendars.first else {
            throw NSError(
                domain: "AppleRemindersSyncService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No Reminders calendars available — user has no Reminders list configured"]
            )
        }
        reminder.calendar = targetCalendar

        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: dueDate
            )
        } else {
            reminder.dueDateComponents = nil
        }

        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    func delete(identifier: String) throws {
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return }
        try store.remove(reminder, commit: true)
    }

    func fetchAllIncompleteReminders() async -> [ImportedReminder] {
        let predicate = store.predicateForReminders(in: nil)
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
    init() {
        startupLog.info("⏱ AppleRemindersSyncService.init() — EKEventStore NOT created yet (lazy)")
    }

    enum AuthorizationState: String {
        case notDetermined
        case restricted
        case denied
        case writeOnly
        case authorized
    }

    private let storage = RemindersStorageActor()

    func authorizationState() -> AuthorizationState {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .writeOnly: return .writeOnly
        case .authorized, .fullAccess: return .authorized
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

    func upsert(_ task: TaskRecord, in context: ModelContext) {
        let state = authorizationState()
        guard state == .authorized || state == .writeOnly else { return }

        let title = task.title
        let notes = task.taskDescription.isEmpty ? task.rawInput : task.taskDescription
        let priority = task.priority.reminderPriority
        let isCompleted = task.completed
        let completionDate = task.completed ? task.updatedAt : nil
        let dueDate = task.dueDate
        let existingIdentifier = task.reminderIdentifier
        let taskID = task.id

        // TODO(bug-hunt): two quick `upsert`s of the same task spawn two
        // unstructured `Task`s. If both read `existingIdentifier == nil` before
        // either writes the identifier back, they create duplicate reminders.
        // Fix by deduping in-flight upserts per task id (e.g. an actor-held
        // [taskID: Task] map that the second call awaits/replaces). Deferred —
        // needs serialization design.
        Task {
            let identifier: String
            do {
                identifier = try await storage.save(
                    title: title,
                    notes: notes,
                    priority: priority,
                    isCompleted: isCompleted,
                    completionDate: completionDate,
                    dueDate: dueDate,
                    existingIdentifier: existingIdentifier
                )
            } catch let error as EKError {
                // EventKit save failed. If the reminder we were tracking has been deleted
                // in the Reminders app (or otherwise rejected), clear the local pointer so
                // the next upsert creates a fresh reminder rather than trying to update a
                // ghost. EventKit doesn't expose a dedicated "not found" code, so on any
                // EKError with a prior identifier we drop it and let the next pass re-create.
                // Mirrors the iOS service's bug-#10 fix.
                if existingIdentifier != nil {
                    await MainActor.run {
                        let descriptor = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == taskID })
                        if let task = try? context.fetch(descriptor).first {
                            task.reminderIdentifier = nil
                            try? context.save()
                        }
                    }
                }
                startupLog.error("AppleRemindersSyncService.upsert failed: \(error.localizedDescription, privacy: .public)")
                return
            } catch {
                startupLog.error("AppleRemindersSyncService.upsert failed: \(error.localizedDescription, privacy: .public)")
                return
            }

            await MainActor.run {
                let descriptor = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == taskID })
                guard let task = try? context.fetch(descriptor).first else { return }
                let priorState = SyncState(rawValue: task.syncStateRawValue) ?? .pendingUpload
                let hadIdentifier = (task.reminderIdentifier?.isEmpty == false)
                task.reminderIdentifier = identifier
                // Explicit branching so future changes can't accidentally
                // resurrect oscillation. Each branch documents intent.
                if !hadIdentifier && priorState == .synced {
                    // Just attached an identifier to a fully-synced task (e.g. freshly
                    // imported from Reminders or matched by title to an existing entry).
                    // No server change needed — keep .synced.
                } else if !hadIdentifier && priorState == .pendingUpload {
                    // Local task got matched/attached to a Reminders entry; keep
                    // .pendingUpload so TaskSyncService eventually persists the
                    // identifier server-side.
                    task.syncState = .pendingUpload
                } else {
                    // Identifier was already set; an actual field change happened — bump.
                    task.syncState = .pendingUpload
                }
                try? context.save()
            }
        }
    }

    func delete(_ task: TaskRecord) {
        let state = authorizationState()
        guard state == .authorized || state == .writeOnly else { return }
        guard let identifier = task.reminderIdentifier else { return }

        Task {
            do {
                try await storage.delete(identifier: identifier)
            } catch {
                AppLogger.shared.log("[Reminders] delete failed for \(identifier): \(error.localizedDescription)")
                // Don't rethrow; caller already moved on. Logging is sufficient for diagnosis.
            }
        }
    }

    func syncAllTasks(_ tasks: [TaskRecord], in context: ModelContext) {
        let state = authorizationState()
        guard state == .authorized || state == .writeOnly else { return }
        for task in tasks {
            upsert(task, in: context)
        }
    }

    func importFromReminders(in context: ModelContext) async {
        guard authorizationState() == .authorized else { return }

        let reminders = await storage.fetchAllIncompleteReminders()
        let descriptor = FetchDescriptor<TaskRecord>()
        let existingTasks = (try? context.fetch(descriptor)) ?? []
        let trackedIdentifiers = Set(existingTasks.compactMap(\.reminderIdentifier))

        // Fallback dedup key: (normalized title, due-date minute bucket).
        // Protects against duplicate inserts when a reminder we already imported
        // has lost its identifier link (e.g. task was created locally first, then
        // the same item came back through the import path).
        func normalizeTitle(_ title: String) -> String {
            title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func dueBucket(_ date: Date?) -> Double {
            guard let date else { return 0 }
            // Round to nearest minute so small clock drift doesn't break dedup.
            return (date.timeIntervalSinceReferenceDate / 60.0).rounded() * 60.0
        }
        var existingTitleBuckets = Set<String>()
        for task in existingTasks {
            let key = "\(normalizeTitle(task.title))|\(dueBucket(task.dueDate))"
            existingTitleBuckets.insert(key)
        }

        var insertedCount = 0
        for reminder in reminders {
            guard !trackedIdentifiers.contains(reminder.identifier) else { continue }
            guard !reminder.title.isEmpty else { continue }

            let fallbackKey = "\(normalizeTitle(reminder.title))|\(dueBucket(reminder.dueDate))"
            if existingTitleBuckets.contains(fallbackKey) { continue }

            let derivedDescription = (reminder.notes.isEmpty || reminder.notes == reminder.title) ? "" : reminder.notes
            let task = TaskRecord(
                rawInput: reminder.title,
                title: reminder.title,
                taskDescription: derivedDescription,
                reminderIdentifier: reminder.identifier,
                dueDate: reminder.dueDate,
                parseState: .parsed,
                syncState: .synced
            )
            context.insert(task)
            // Track the new task's fallback key so subsequent reminders in the
            // same batch don't insert a near-duplicate.
            existingTitleBuckets.insert(fallbackKey)
            insertedCount += 1
        }

        if insertedCount > 0 {
            try? context.save()
            AppLogger.shared.log("importFromReminders: inserted \(insertedCount) reminder(s) as tasks")
        }
    }
}

// MARK: - Priority Mapping

private extension AppTaskPriority {
    // EKReminder.priority: 0 = none, 1 = highest, 5 = medium, 9 = lowest.
    var reminderPriority: Int {
        switch self {
        case .none: return 0
        case .low: return 9
        case .medium: return 5
        case .high: return 1
        }
    }
}
