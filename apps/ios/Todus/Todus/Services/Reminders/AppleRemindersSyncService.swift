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
actor RemindersStorageActor {
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

    /// Result of a save operation — `identifier` is the calendarItemIdentifier of the saved
    /// reminder; `existingNotFound` is true when the caller passed an `existingIdentifier`
    /// but the reminder no longer exists in the system (e.g. the user deleted it from the
    /// Reminders app). The caller should clear the local pointer in that case.
    struct SaveResult: Sendable {
        let identifier: String
        let existingNotFound: Bool
    }

    /// Creates or updates a reminder. Returns a `SaveResult` indicating the new identifier
    /// and whether the previously-tracked reminder had been deleted out from under us.
    func save(
        title: String,
        notes: String,
        priority: Int,
        isCompleted: Bool,
        completionDate: Date?,
        dueDate: Date?,
        existingIdentifier: String?
    ) throws -> SaveResult {
        // Reuse existing reminder if we have a valid identifier, otherwise create a new one.
        // If we were given an identifier but the lookup fails, the reminder was deleted
        // externally — fall back to creating a fresh one and tell the caller to clear the
        // stale local pointer (bug #10: ghost task on Reminders deletion).
        let existing = existingIdentifier.flatMap {
            store.calendarItem(withIdentifier: $0) as? EKReminder
        }
        let existingNotFound = existingIdentifier != nil && existing == nil
        let reminder = existing ?? EKReminder(eventStore: store)

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
        return SaveResult(
            identifier: reminder.calendarItemIdentifier,
            existingNotFound: existingNotFound
        )
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

    /// Sendable status snapshot for tracked reminders — used to propagate
    /// completion state back from Apple Reminders to local TaskRecords (#6).
    struct ReminderStatus: Sendable {
        let identifier: String
        let isCompleted: Bool
        let completionDate: Date?
    }

    /// Look up specific reminders by `calendarItemIdentifier` and return their
    /// completion state. Includes both completed and incomplete entries so the
    /// caller can detect a Reminders-side check-off and mirror it locally.
    func fetchTrackedReminders(identifiers: [String]) -> [ReminderStatus] {
        guard !identifiers.isEmpty else { return [] }
        var out: [ReminderStatus] = []
        for id in identifiers {
            if let r = store.calendarItem(withIdentifier: id) as? EKReminder {
                out.append(ReminderStatus(
                    identifier: id,
                    isCompleted: r.isCompleted,
                    completionDate: r.completionDate
                ))
            }
        }
        return out
    }
}

// MARK: - Storage seam

/// EventKit-backed storage seam — abstracts the small subset of `EKEventStore`
/// surface that `AppleRemindersSyncService` uses (save / delete / fetch +
/// authorization). The production impl is `RemindersStorageActor`; tests
/// inject a fake that records calls and returns canned `SaveResult` / status
/// values without touching the device Reminders database.
protocol EKReminderStoring: Sendable {
    func requestFullAccess() async throws -> Bool
    func save(
        title: String,
        notes: String,
        priority: Int,
        isCompleted: Bool,
        completionDate: Date?,
        dueDate: Date?,
        existingIdentifier: String?
    ) async throws -> RemindersStorageActor.SaveResult
    func delete(identifier: String) async throws
    func fetchAllIncompleteReminders() async -> [ImportedReminder]
    func fetchTrackedReminders(identifiers: [String]) async -> [RemindersStorageActor.ReminderStatus]
}

extension RemindersStorageActor: EKReminderStoring {}

// MARK: - Service

@MainActor
final class AppleRemindersSyncService {
    /// Convenience init that uses the production `RemindersStorageActor`. Kept
    /// as the public entry point so existing call sites compile unchanged.
    convenience init() {
        self.init(storage: RemindersStorageActor(), authorizationProbe: nil)
    }

    /// Internal designated init that accepts an `EKReminderStoring` and an
    /// optional authorization-state override. Used by unit tests to inject
    /// a fake storage and bypass the EKEventStore authorization gate so
    /// the upsert / reconcile branches can be exercised without permissions.
    init(storage: EKReminderStoring, authorizationProbe: (@MainActor () -> AuthorizationState)?) {
        startupLog.info("⏱ AppleRemindersSyncService.init() — EKEventStore NOT created yet (lazy)")
        self.storage = storage
        self.authorizationProbe = authorizationProbe
    }

    /// Test-only override for `authorizationState()`. When non-nil, used in
    /// place of `EKEventStore.authorizationStatus(for: .reminder)` so tests
    /// can drive code paths gated on `.authorized`.
    private let authorizationProbe: (@MainActor () -> AuthorizationState)?
    enum AuthorizationState: String {
        case notDetermined
        case restricted
        case denied
        case authorized
    }

    // Single shared storage instance — its serial queue serializes all EKEventStore I/O.
    private let storage: EKReminderStoring

    /// Per-task in-flight set so concurrent capture+enrich passes don't both try to
    /// create a fresh EKReminder before the first upsert returns its identifier
    /// (#20). Keys are local task UUIDs; presence means an upsert is in flight.
    private var inFlightUpserts: Set<UUID> = []
    /// Coalescing buffer — a second upsert that arrives while the first is in flight
    /// is recorded here; we re-fire it once the first completes so the latest data
    /// wins without an additional EK reminder being created.
    private var pendingUpsertTaskIDs: Set<UUID> = []
    /// Per-task drain-retry counter, bounding how many times a coalesced re-upsert
    /// can chain. Without this a hot loop of mutations could keep re-firing
    /// `upsert(...)` recursively. (Medium bug — recursive upsert with no max-attempts.)
    private var coalescedRetryCount: [UUID: Int] = [:]
    private let maxCoalescedRetries = 3

    /// Current sync direction. Owned at the AppServices layer (in `RemindersSyncState`);
    /// kept mirrored here so consumers that already hold this service can read
    /// `isOneWaySync` without reaching back into AppServices. AppServices is responsible
    /// for keeping this in sync with `RemindersSyncState.direction`.
    var syncDirection: RemindersSyncDirection = .twoWay

    /// `true` when the user has set sync to pull-only (Reminders → Todus). When this is true,
    /// upserts/deletes from Todus → Reminders are intentionally suppressed by the callers
    /// in `TaskCaptureService.syncReminder` / `deleteReminder`. UIs read this to display a
    /// "one-way sync" label so users aren't surprised when local edits don't propagate.
    var isOneWaySync: Bool { syncDirection == .fromReminders }

    func authorizationState() -> AuthorizationState {
        // Tests inject an override via `authorizationProbe` so they can drive
        // permission-gated branches without prompting the user.
        if let probe = authorizationProbe { return probe() }
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

        // Coalesce concurrent upserts for the same task. Without this, a capture
        // pass that calls upsert(...) before EKEventStore.save returns the
        // identifier, followed by an enrichment pass that calls upsert(...)
        // again, both see existingIdentifier=nil → both create new EKReminders
        // (duplicate Reminders entries).
        if inFlightUpserts.contains(task.id) {
            pendingUpsertTaskIDs.insert(task.id)
            return
        }
        inFlightUpserts.insert(task.id)

        // Capture only Sendable (value-type) data from the task before leaving the main actor.
        let title = task.title
        // Push only the user-curated description. Falling back to `rawInput`
        // dumps the full natural-language capture (e.g. "Buy milk tomorrow at
        // 5pm") into the Reminders notes field, which then round-trips back as
        // a permanent task description on the next import.
        let notes = task.taskDescription
        let priority = task.priority.reminderPriority
        let isCompleted = task.completed
        // Use the dedicated `completedAt` stamp (set on false→true transition in
        // TaskRecord) so Reminders' Completed smart list shows the actual moment
        // the task was checked off. Fall back to `updatedAt` only when a legacy
        // task is missing `completedAt` (older rows pre-dating the field).
        let completionDate: Date? = task.completed ? (task.completedAt ?? task.updatedAt) : nil
        let dueDate = task.dueDate
        let existingIdentifier = task.reminderIdentifier
        let taskID = task.id

        // Task { } inherits @MainActor isolation; the `await storage.save(...)` suspends
        // this task (freeing the main thread) while the storage actor does the XPC work.
        // After the await, execution resumes on the main actor to update SwiftData safely.
        Task {
            let result: RemindersStorageActor.SaveResult
            do {
                result = try await storage.save(
                    title: title,
                    notes: notes,
                    priority: priority,
                    isCompleted: isCompleted,
                    completionDate: completionDate,
                    dueDate: dueDate,
                    existingIdentifier: existingIdentifier
                )
            } catch let error as EKError {
                // EventKit save failed. If the reminder we were tracking has been deleted in
                // the Reminders app (or otherwise rejected), clear the local pointer so the
                // next upsert creates a fresh reminder rather than trying to update a ghost.
                // EventKit doesn't expose a dedicated "not found" code, so on any EKError with
                // a prior identifier we drop it and let the next pass re-create.
                if existingIdentifier != nil {
                    let descriptor = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == taskID })
                    if let task = try? context.fetch(descriptor).first {
                        task.reminderIdentifier = nil
                        try? context.save()
                    }
                }
                AppLogger.shared.log("AppleRemindersSyncService.upsert failed: \(error.localizedDescription)")
                self.inFlightUpserts.remove(taskID)
                self.pendingUpsertTaskIDs.remove(taskID)
                return
            } catch {
                AppLogger.shared.log("AppleRemindersSyncService.upsert failed: \(error.localizedDescription)")
                self.inFlightUpserts.remove(taskID)
                self.pendingUpsertTaskIDs.remove(taskID)
                return
            }

            // Back on the main actor — safe to use the SwiftData ModelContext.
            let descriptor = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == taskID })
            guard let task = try? context.fetch(descriptor).first else { return }
            // If the previously-tracked reminder was missing, our save() created a fresh
            // one; either way we now point at a live identifier.
            let identifierChanged = task.reminderIdentifier != result.identifier
            task.reminderIdentifier = result.identifier
            // Only mark pendingUpload when the identifier actually changed so the backend
            // learns the new link. Resetting it unconditionally was re-queuing every task
            // for a redundant backend sync after each reminder save.
            if identifierChanged {
                task.syncState = .pendingUpload
            }
            if result.existingNotFound {
                AppLogger.shared.log(
                    "AppleRemindersSyncService.upsert: previous reminder missing, recreated as \(result.identifier)"
                )
            }
            try? context.save()

            // Drain coalesced re-upserts. If a second upsert arrived while this one
            // was in flight, re-fire it now with the up-to-date task state — but
            // *with* the freshly-written reminderIdentifier so it won't create a
            // duplicate EKReminder.
            //
            // Bounded to `maxCoalescedRetries` to prevent a hot loop of mutations
            // from chaining upserts indefinitely. (Medium bug.)
            self.inFlightUpserts.remove(taskID)
            if self.pendingUpsertTaskIDs.remove(taskID) != nil {
                let attempts = (self.coalescedRetryCount[taskID] ?? 0) + 1
                if attempts >= self.maxCoalescedRetries {
                    AppLogger.shared.log(
                        "AppleRemindersSyncService.upsert: dropped coalesced re-upsert for \(taskID) after \(attempts) attempts"
                    )
                    self.coalescedRetryCount[taskID] = nil
                } else {
                    self.coalescedRetryCount[taskID] = attempts
                    if let refreshed = try? context.fetch(descriptor).first {
                        self.upsert(refreshed, in: context)
                    }
                }
            } else {
                // Clean exit — reset the retry counter for this task.
                self.coalescedRetryCount[taskID] = nil
            }
        }
    }

    /// Public entry point for re-importing reminders at runtime (e.g. on app foreground).
    /// Mirrors `importFromReminders` but is called explicitly from views — `importFromReminders`
    /// is intended for the onboarding path and is no longer the only way to refresh.
    func refreshFromReminders(in context: ModelContext) async {
        // Import-only: never auto-complete tasks based on Reminders state.
        // reconcileCompletionFromReminders was removed from this path because it
        // silently marked Todus-only tasks as done when the manual sync button
        // was tapped, causing tasks to "disappear" from the active list.
        await importFromReminders(in: context)
    }

    // MARK: - Reminders → Todus reconciliation
    //
    // **One-way semantics intentional.** This function only propagates
    // Reminders → Todus for "marked done" — we do NOT reopen a Todus task
    // when the user unchecks the matching reminder. Local Todus edits are
    // authoritative for un-completion to avoid racing the "user just
    // unchecked it locally" pathway. When `syncDirection == .twoWay` and the
    // user explicitly wants reopen-on-uncheck, that flow lives elsewhere
    // (TODO: not yet implemented — see medium bug 340-357).
    //
    /// For every locally-tracked reminder, propagate its completion state back
    /// to the matching TaskRecord.
    func reconcileCompletionFromReminders(in context: ModelContext) async {
        guard authorizationState() == .authorized else { return }
        let descriptor = FetchDescriptor<TaskRecord>()
        let allTasks = (try? context.fetch(descriptor)) ?? []
        let identifiers = allTasks.compactMap(\.reminderIdentifier)
        guard !identifiers.isEmpty else { return }

        let statuses = await storage.fetchTrackedReminders(identifiers: identifiers)
        guard !statuses.isEmpty else { return }
        let byID = Dictionary(uniqueKeysWithValues: statuses.map { ($0.identifier, $0) })

        var changed = 0
        var divergedOpenInReminders = 0
        for task in allTasks {
            guard let id = task.reminderIdentifier, let status = byID[id] else { continue }
            // Only propagate true → done. See MARK: block above for rationale.
            if status.isCompleted && !task.completed {
                // NOTE: the previous version inserted/removed `task.id` into
                // `inFlightUpserts` here as a "suppress the next upsert" guard,
                // but no upsert path is invoked from this method — the
                // insert/remove pair was a no-op. Removed to avoid misleading
                // future readers. (Medium bug 340-358.)
                task.completed = true
                task.status = .done
                if let when = status.completionDate {
                    task.updatedAt = when
                }
                changed += 1
            } else if !status.isCompleted && task.completed {
                // Divergence: Reminders shows open but Todus has it closed.
                // Currently always one-way (see MARK: above) — log so we can
                // measure how often users expect reopen-on-uncheck.
                // (Medium bug 340-357.)
                divergedOpenInReminders += 1
            }
        }
        if changed > 0 {
            try? context.save()
            AppLogger.shared.log("reconcileCompletionFromReminders: marked \(changed) task(s) done from Reminders")
        }
        if divergedOpenInReminders > 0 {
            AppLogger.shared.log(
                "reconcileCompletionFromReminders: \(divergedOpenInReminders) task(s) open in Reminders but done in Todus (one-way sync — not reopening)"
            )
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

        // Guard against the race where a Todus-created task's upsert() async Task hasn't yet
        // written reminderIdentifier back to the TaskRecord. The reminder already exists in
        // Apple Reminders but reminderIdentifier is still nil, so trackedIdentifiers misses it
        // and importFromReminders would create a duplicate. Skip any reminder whose title
        // matches a local task that is pending upload and has no reminder link yet.
        let pendingTitles = Set(
            existingTasks
                .filter { $0.reminderIdentifier == nil && $0.syncState == .pendingUpload }
                .map { $0.title }
        )

        var insertedCount = 0
        for reminder in reminders {
            guard !trackedIdentifiers.contains(reminder.identifier) else { continue }
            guard !pendingTitles.contains(reminder.title) else { continue }
            guard !reminder.title.isEmpty else { continue }

            // Mark as `parsed` (title already set — no AI enrichment needed) and
            // `synced` (originated in Reminders, nothing to push back right now).
            // Only store notes as description if it's non-empty and differs from the title.
            // When upsert() syncs a title-only task to Reminders, it writes rawInput into the
            // notes field — causing a round-trip where notes == title, producing visible
            // duplication in TaskRowView. Clearing it here prevents that.
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
            insertedCount += 1
        }

        if insertedCount > 0 {
            try? context.save()
            AppLogger.shared.log("importFromReminders: inserted \(insertedCount) reminder(s) as tasks")
        }
    }

    // MARK: - Test-only accessors

    /// Test-only readback of the in-flight upsert set. Used by
    /// `AppleRemindersSyncServiceTests` to verify the set drains after an
    /// EK error path. Not for production use.
    var _test_inFlightUpserts: Set<UUID> { inFlightUpserts }
    /// Test-only readback of the per-task coalesced-retry counter.
    var _test_coalescedRetryCount: [UUID: Int] { coalescedRetryCount }
    /// Test-only adder for the pending coalesce buffer. Used to simulate the
    /// "second upsert arrived while first was in flight" race.
    func _test_recordPendingUpsert(_ id: UUID) {
        pendingUpsertTaskIDs.insert(id)
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
