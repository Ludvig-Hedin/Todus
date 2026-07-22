import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class TaskCaptureService {
    private let parser: TaskParsingService
    private let syncService: SyncService
    private let authStore: AuthSessionStore
    private let remindersSyncService: AppleRemindersSyncService
    private let remindersSyncState: RemindersSyncState
    /// Internal (not private) so the organize extension in
    /// `TaskOrganizeService.swift` can reach the backend.
    let apiClient: TodosAPIClient
    /// Offline mutation queue for folder create/update/delete operations.
    /// Shared with AppServices so all folder mutations flow through one queue.
    let folderSyncService: FolderSyncService

    /// Optional notification service — set after init by AppServices.
    /// Schedules local reminders when tasks have due dates.
    var notificationService: NotificationService?
    /// Whether task reminders are enabled — read from AppServices at schedule time.
    var taskRemindersEnabled: Bool = true
    /// Number of tasks rolled back during the most recent capture-time sync failure.
    /// Views observe this to surface a banner; remains 0 until a rollback occurs.
    /// (Class is `@Observable`, so direct mutations are tracked like `@Published`.)
    private(set) var lastRollbackCount: Int = 0
    /// Timestamp of the most recent rollback, paired with `lastRollbackCount` so the UI
    /// can debounce repeated banner displays.
    private(set) var lastRollbackAt: Date?
    /// Number of lines dropped from the most recent bulk-capture submission because it
    /// exceeded `maxBulkCaptureLines`. Views observe this to surface a truncation banner;
    /// remains 0 until a truncation occurs. Mirrors `lastRollbackCount`/`lastRollbackAt`.
    private(set) var lastTruncatedCount: Int = 0
    /// Timestamp of the most recent truncation, paired with `lastTruncatedCount` so the
    /// UI can debounce repeated banner displays.
    private(set) var lastTruncatedAt: Date?
    private var lastSharedFolderSyncAt: Date?
    private(set) var isSyncingSharedFolders = false
    private var sharedFolderAccountGeneration: UInt64 = 0
    private var sharedFolderSyncGeneration: UInt64?
    private let sharedFolderSyncInterval: TimeInterval = 60

    init(
        parser: TaskParsingService,
        syncService: SyncService,
        authStore: AuthSessionStore,
        remindersSyncService: AppleRemindersSyncService,
        remindersSyncState: RemindersSyncState,
        apiClient: TodosAPIClient,
        folderSyncService: FolderSyncService
    ) {
        self.parser = parser
        self.syncService = syncService
        self.authStore = authStore
        self.remindersSyncService = remindersSyncService
        self.remindersSyncState = remindersSyncState
        self.apiClient = apiClient
        self.folderSyncService = folderSyncService
    }

    /// Drops account-scoped refresh throttles so a different user who signs in
    /// immediately does not inherit the previous account's one-minute folder cache.
    func resetForSignOut() {
        sharedFolderAccountGeneration &+= 1
        lastSharedFolderSyncAt = nil
        sharedFolderSyncGeneration = nil
        isSyncingSharedFolders = false
    }

    /// Removes mirrors owned by a task only after a remote tombstone has been
    /// committed to the local SwiftData store.
    func handleRemoteTaskDeletion(id: UUID, reminderIdentifier: String?) {
        deleteReminder(identifier: reminderIdentifier)
        notificationService?.cancelTaskReminder(taskID: id.uuidString)
    }

    /// Captures one or more tasks from raw text, optionally with attachment filenames,
    /// a manually selected folder, and an override due date.
    /// Attachments are only applied to the first task when multi-line input is used,
    /// since they logically belong to the first captured thought.
    func capture(
        rawComposerText: String,
        attachmentNames: [String] = [],
        selectedFolder: FolderRecord? = nil,
        overrideDueDate: Date? = nil,
        in context: ModelContext,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        let lines = Self.splitInputLines(rawComposerText)
        guard !lines.isEmpty else { return }

        // Surface truncation to observers so the UI can tell the user some lines were
        // dropped instead of silently accepting only the first `maxBulkCaptureLines`.
        // Recompute the pre-cap line count the same way `splitInputLines` does rather
        // than changing that function's (pure, tested) signature.
        let rawLineCount = rawComposerText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
        if rawLineCount > Self.maxBulkCaptureLines {
            lastTruncatedCount = rawLineCount - Self.maxBulkCaptureLines
            lastTruncatedAt = Date()
        }

        var mutations: [SyncMutation] = []
        // Capture (taskID, rawInput) pairs so enrichment can only run for the
        // tasks that survive the initial sync round-trip. (Bug H8 — previously
        // queueEnrichment was fired inline in this loop, racing the rollback
        // path and leaving enrichment to update a now-deleted record.)
        var enrichmentInputs: [(taskID: UUID, rawInput: String)] = []

        for (index, line) in lines.enumerated() {
            let now = Date()
            // Only the first task gets the attachments (they belong to the original input)
            let taskAttachments = index == 0 ? attachmentNames : []
            let task = TaskRecord(
                rawInput: line,
                title: Self.instantTitle(from: line),
                taskDescription: "",
                completed: false,
                status: .todo,
                priority: .none,
                attachmentNames: taskAttachments,
                reminderIdentifier: nil,
                createdAt: now,
                updatedAt: now,
                // Apply manually chosen folder and due date if provided
                dueDate: overrideDueDate,
                folder: selectedFolder,
                parseState: .pending,
                syncState: .pendingUpload
            )
            context.insert(task)
            syncReminder(task, in: context)
            scheduleNotificationIfNeeded(task)
            mutations.append(SyncMutation(action: .upsert, task: task.asPayload(), taskID: task.id))
            enrichmentInputs.append((taskID: task.id, rawInput: line))
        }

        // Surface save errors instead of swallowing — disk-full / iCloud quota / corrupt
        // store would previously have failed silently here. (Medium bug.)
        do {
            try context.save()
        } catch {
            context.rollback()
            AppLogger.shared.log("TaskCaptureService.capture: save failed: \(error.localizedDescription)")
            lastRollbackCount = mutations.count
            lastRollbackAt = .now
            return
        }

        Task { @MainActor [weak self, syncService] in
            await syncService.enqueue(mutations, in: context)
            // Remote sync is best-effort. Never delete a task the user just created
            // because a network/backend acknowledgement failed; pending rows retry.
            guard let self else { return }
            for entry in enrichmentInputs {
                self.queueEnrichment(
                    for: entry.taskID,
                    rawInput: entry.rawInput,
                    locale: locale,
                    timeZone: timeZone,
                    in: context
                )
            }
        }
    }

    /// Quick-capture a single task into a specific status column (used by board view inline add)
    func captureInStatus(
        title: String,
        status: TaskStatus,
        folder: FolderRecord? = nil,
        in context: ModelContext
    ) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let now = Date()
        let task = TaskRecord(
            rawInput: cleaned,
            title: cleaned,
            taskDescription: "",
            completed: status == .done,
            status: status,
            priority: .none,
            attachmentNames: [],
            reminderIdentifier: nil,
            createdAt: now,
            updatedAt: now,
            dueDate: nil,
            folder: folder,
            parseState: .parsed,
            syncState: .pendingUpload
        )
        context.insert(task)
        syncReminder(task, in: context)
        scheduleNotificationIfNeeded(task)
        try? context.save()

        Task { @MainActor [syncService] in
            await syncService.enqueue([SyncMutation(action: .upsert, task: task.asPayload(), taskID: task.id)], in: context)
        }
    }

    func toggleCompletion(_ task: TaskRecord, in context: ModelContext) {
        setStatus(task, status: task.completed ? .todo : .done, in: context)
    }

    func setStatus(_ task: TaskRecord, status: TaskStatus, in context: ModelContext) {
        task.status = status
        task.updatedAt = .now
        task.syncState = .pendingUpload
        persist(task: task, in: context)
        syncReminder(task, in: context)
        if status == .done {
            // Cancel notification when task is completed
            notificationService?.cancelTaskReminder(taskID: task.id.uuidString)
        } else if status == .todo {
            // Reschedule notification when task transitions back to .todo with a future due date
            scheduleNotificationIfNeeded(task)
        }
    }

    func updateTitle(_ task: TaskRecord, title: String, in context: ModelContext) {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else { return }
        task.title = cleanedTitle
        task.updatedAt = .now
        task.parseState = .parsed
        task.syncState = .pendingUpload
        persist(task: task, in: context)
        syncReminder(task, in: context)
    }

    func updatePriority(_ task: TaskRecord, priority: AppTaskPriority, in context: ModelContext) {
        guard task.priority != priority else { return }
        task.priority = priority
        task.updatedAt = .now
        task.syncState = .pendingUpload
        persist(task: task, in: context)
        syncReminder(task, in: context)
    }

    func updateTaskDetails(
        _ task: TaskRecord,
        title: String,
        taskDescription: String,
        status: TaskStatus,
        priority: AppTaskPriority,
        dueDate: Date?,
        folder: FolderRecord?,
        attachmentNames: [String],
        in context: ModelContext
    ) {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else { return }

        task.title = cleanedTitle
        task.taskDescription = taskDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        task.status = status
        task.priority = priority
        task.dueDate = dueDate
        task.folder = folder
        task.attachmentNames = attachmentNames
        task.updatedAt = .now
        task.parseState = .parsed
        task.syncState = .pendingUpload
        persist(task: task, in: context)
        syncReminder(task, in: context)
        // Cancel notification when marking done via detail sheet, then reschedule if still active
        if status == .done {
            notificationService?.cancelTaskReminder(taskID: task.id.uuidString)
        } else {
            scheduleNotificationIfNeeded(task)
        }
    }

    /// Defer this task by setting the due date to a later moment.
    /// Used by the row swipe-trailing "Snooze" gesture.
    func snooze(_ task: TaskRecord, until date: Date, in context: ModelContext) {
        task.dueDate = date
        task.updatedAt = .now
        task.syncState = .pendingUpload
        persist(task: task, in: context)
        syncReminder(task, in: context)
        scheduleNotificationIfNeeded(task)
    }

    func move(_ task: TaskRecord, to folder: FolderRecord?, in context: ModelContext) {
        task.folder = folder
        task.updatedAt = .now
        task.syncState = .pendingUpload
        persist(task: task, in: context)
        syncReminder(task, in: context)
    }

    func delete(_ task: TaskRecord, in context: ModelContext) {
        let mutation = SyncMutation(action: .delete, task: nil, taskID: task.id)
        let reminderIdentifier = task.reminderIdentifier
        let taskID = task.id.uuidString
        context.delete(task)
        // Only enqueue the remote delete if the local deletion actually persisted.
        // Swallowing this previously could leave the task in the local store while
        // still deleting it on the backend — a sync-state mismatch on next sync.
        do {
            try context.save()
        } catch {
            context.rollback()
            AppLogger.shared.log("TaskCaptureService.delete: save failed: \(error.localizedDescription)")
            return
        }

        deleteReminder(identifier: reminderIdentifier)
        notificationService?.cancelTaskReminder(taskID: taskID)

        Task { @MainActor [syncService] in
            await syncService.enqueue([mutation], in: context)
        }
    }

    func clearCompletedTasks(filteredBy folderID: UUID?, in context: ModelContext) {
        // Skip models already deleted but not yet saved — touching them mutates
        // deleted PersistentModels, a known SwiftData crash vector. (TD-13)
        let tasks = ((try? context.fetch(FetchDescriptor<TaskRecord>())) ?? []).filter { task in
            !task.isDeleted && task.status == .done && (folderID == nil || task.folderID == folderID)
        }

        guard !tasks.isEmpty else { return }

        let deletions = tasks.map { task in
            (
                mutation: SyncMutation(action: .delete, task: nil, taskID: task.id),
                reminderIdentifier: task.reminderIdentifier
            )
        }
        let mutations = deletions.map(\.mutation)

        for task in tasks {
            context.delete(task)
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            AppLogger.shared.log(
                "TaskCaptureService.clearCompletedTasks: save failed: \(error.localizedDescription)"
            )
            return
        }

        for deletion in deletions {
            deleteReminder(identifier: deletion.reminderIdentifier)
        }

        Task { @MainActor [syncService] in
            await syncService.enqueue(mutations, in: context)
        }
    }

    /// Outcome of an explicit "create new folder" attempt. Distinguishes a real
    /// creation from a case-insensitive name collision so create UIs can surface
    /// the duplicate instead of silently returning the old folder (which dropped
    /// the user's chosen color/icon and faked success).
    enum CreateFolderOutcome {
        case created(FolderRecord)
        case duplicate(FolderRecord)
        case invalidName
    }

    /// Get-or-create semantics: a name collision returns the existing folder.
    /// Use `createFolderExclusive` when the user is explicitly creating a new
    /// folder and a collision should be surfaced as an error.
    func createFolder(
        named name: String,
        colorHex: String? = nil,
        iconName: String? = nil,
        in context: ModelContext
    ) -> FolderRecord? {
        switch createFolderExclusive(named: name, colorHex: colorHex, iconName: iconName, in: context) {
        case .created(let folder), .duplicate(let folder):
            return folder
        case .invalidName:
            return nil
        }
    }

    func createFolderExclusive(
        named name: String,
        colorHex: String? = nil,
        iconName: String? = nil,
        in context: ModelContext
    ) -> CreateFolderOutcome {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return .invalidName }

        let existing = (try? context.fetch(FetchDescriptor<FolderRecord>())) ?? []

        if let existingFolder = existing.first(where: { $0.name.compare(cleanedName, options: .caseInsensitive) == .orderedSame }) {
            return .duplicate(existingFolder)
        }

        let nextPosition = (existing.map { $0.position }.max() ?? -1) + 1
        let folder = FolderRecord(
            name: cleanedName,
            colorHex: colorHex,
            iconName: iconName,
            position: nextPosition
        )
        context.insert(folder)
        try? context.save()
        Task {
            await folderSyncService.enqueue(
                .upsert(
                    id: folder.id.uuidString,
                    name: folder.name,
                    color: folder.colorHex,
                    icon: folder.iconName,
                    position: folder.position
                )
            )
        }
        return .created(folder)
    }

    func renameFolder(_ folder: FolderRecord, to name: String, in context: ModelContext) {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return }

        folder.name = cleanedName
        folder.updatedAt = .now
        try? context.save()
        Task {
            await folderSyncService.enqueue(
                .upsert(
                    id: folder.id.uuidString,
                    name: folder.name,
                    color: folder.colorHex,
                    icon: folder.iconName,
                    position: folder.position
                )
            )
        }
    }

    /// Update color and/or icon. Pass nil to clear, or omit to leave unchanged.
    func updateFolderAppearance(
        _ folder: FolderRecord,
        colorHex: String?? = nil,
        iconName: String?? = nil,
        in context: ModelContext
    ) {
        if case let .some(value) = colorHex { folder.colorHex = value }
        if case let .some(value) = iconName { folder.iconName = value }
        folder.updatedAt = .now
        try? context.save()
        Task {
            await folderSyncService.enqueue(
                .upsert(
                    id: folder.id.uuidString,
                    name: folder.name,
                    color: folder.colorHex,
                    icon: folder.iconName,
                    position: folder.position
                )
            )
        }
    }

    /// Persist a new ordering. Updates the `position` field of each folder
    /// to match its index in the array, then syncs to the backend.
    func reorderFolders(_ orderedFolders: [FolderRecord], in context: ModelContext) {
        for (index, folder) in orderedFolders.enumerated() {
            if folder.position != index {
                folder.position = index
                folder.updatedAt = .now
            }
        }
        try? context.save()
        // Encode each repositioned folder as an upsert mutation so position changes
        // are durable across reconnects (the legacy reorder endpoint had no offline queue).
        let snapshots = orderedFolders.map { f in
            FolderSyncService.Mutation.upsert(
                id: f.id.uuidString,
                name: f.name,
                color: f.colorHex,
                icon: f.iconName,
                position: f.position
            )
        }
        Task {
            for mutation in snapshots {
                await folderSyncService.enqueue(mutation)
            }
        }
    }

    func deleteFolder(_ folder: FolderRecord, in context: ModelContext) {
        let folderId = folder.id.uuidString
        // Use in-memory filtering: folderID is a computed property on TaskRecord,
        // so it cannot be used in a SwiftData #Predicate (runtime crash).
        let allTasks = (try? context.fetch(FetchDescriptor<TaskRecord>())) ?? []
        let linkedTasks = allTasks.filter { $0.folder?.id == folder.id }
        let mutations = linkedTasks.map { task -> SyncMutation in
            task.folder = nil
            task.updatedAt = .now
            task.syncState = .pendingUpload
            return SyncMutation(action: .upsert, task: task.asPayload(), taskID: task.id)
        }
        context.delete(folder)
        try? context.save()
        Task { @MainActor [syncService, folderSyncService] in
            if !mutations.isEmpty {
                await syncService.enqueue(mutations, in: context)
            }
            await folderSyncService.enqueue(.delete(id: folderId))
        }
    }

    func syncSharedFolders(in context: ModelContext) async {
        let now = Date()
        let generation = sharedFolderAccountGeneration
        if sharedFolderSyncGeneration == generation {
            return
        }
        if let lastSharedFolderSyncAt,
           now.timeIntervalSince(lastSharedFolderSyncAt) < sharedFolderSyncInterval {
            return
        }

        struct FolderListResponse: Decodable {
            let folders: [RemoteFolder]
        }

        let trace = PerformanceTrace.beginInterval(
            PerformanceTrace.sharedFolderSync,
            message: "TaskCaptureService.syncSharedFolders begin"
        )
        sharedFolderSyncGeneration = generation
        isSyncingSharedFolders = true
        defer {
            if sharedFolderSyncGeneration == generation {
                sharedFolderSyncGeneration = nil
                isSyncingSharedFolders = false
            }
            PerformanceTrace.endInterval(
                PerformanceTrace.sharedFolderSync,
                trace,
                message: "TaskCaptureService.syncSharedFolders end"
            )
        }

        do {
            let response: FolderListResponse = try await apiClient.trpcQuery("folders.list")
            guard generation == sharedFolderAccountGeneration else { return }
            let remoteFolders = response.folders
            let localFolders = (try? context.fetch(FetchDescriptor<FolderRecord>())) ?? []
            // Keyed by parsed UUID, not uuidString: Swift renders uuidString UPPERCASE
            // while server/web-created folders use lowercase ids, so a raw string
            // lookup missed every remote folder and re-inserted a duplicate per sync.
            var foldersByID = Dictionary(uniqueKeysWithValues: localFolders.map { ($0.id, $0) })

            for remote in remoteFolders {
                guard let uuid = UUID(uuidString: remote.id) else { continue }
                if let local = foldersByID[uuid] {
                    // Skip the server-wins overwrite while a local mutation for this
                    // folder is still queued/in flight — a stale list response would
                    // otherwise revert an in-flight rename. The pending upsert pushes
                    // local state up; the next sync pass reconciles. (TD-21a)
                    // uuid.uuidString matches the uppercase ids used at enqueue time.
                    if folderSyncService.hasPending(id: uuid.uuidString) { continue }
                    local.name = remote.name
                    local.colorHex = remote.color
                    local.iconName = remote.icon
                    local.position = remote.position ?? local.position
                    local.createdAt = remote.createdAt
                    local.updatedAt = remote.updatedAt ?? local.updatedAt
                } else {
                    let folder = FolderRecord(
                        id: uuid,
                        name: remote.name,
                        colorHex: remote.color,
                        iconName: remote.icon,
                        position: remote.position ?? 0,
                        createdAt: remote.createdAt,
                        updatedAt: remote.updatedAt ?? remote.createdAt
                    )
                    context.insert(folder)
                    foldersByID[uuid] = folder
                }
            }

            do {
                guard generation == sharedFolderAccountGeneration else { return }
                try context.save()
                lastSharedFolderSyncAt = now
            } catch {
                AppLogger.shared.log("[TaskCaptureService] Failed to save shared folders: \(error)")
            }
        } catch {
            // Folder sync is best-effort; local folders remain usable offline.
        }
    }

    /// Cap on number of tasks accepted from a single paste / multi-line composer
    /// submission. A flatfile paste of hundreds of lines would otherwise spawn
    /// hundreds of sync mutations + Reminders writes synchronously here.
    /// (Medium bug — TaskCaptureService no cap on splitInputLines.)
    /// UI confirmation when extras are dropped: see `lastTruncatedCount`/`lastTruncatedAt`
    /// below, surfaced via `MainTabView`'s truncation banner.
    nonisolated static let maxBulkCaptureLines = 50

    nonisolated static func splitInputLines(_ rawText: String) -> [String] {
        let trimmed = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if trimmed.count > maxBulkCaptureLines {
            AppLogger.shared.log(
                "TaskCaptureService.splitInputLines: dropping \(trimmed.count - maxBulkCaptureLines) line(s) over cap (\(maxBulkCaptureLines))"
            )
            return Array(trimmed.prefix(maxBulkCaptureLines))
        }
        return trimmed
    }

    nonisolated static func instantTitle(from rawText: String) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New task" : trimmed
    }

    private func persist(task: TaskRecord, in context: ModelContext) {
        let trace = PerformanceTrace.beginInterval(
            PerformanceTrace.saveContext,
            message: "TaskCaptureService.persist begin task=\(task.id.uuidString)"
        )
        try? context.save()
        PerformanceTrace.endInterval(
            PerformanceTrace.saveContext,
            trace,
            message: "TaskCaptureService.persist end task=\(task.id.uuidString)"
        )
        let mutation = SyncMutation(action: .upsert, task: task.asPayload(), taskID: task.id)
        Task { @MainActor [syncService] in
            await syncService.enqueue([mutation], in: context)
        }
    }

    private func queueEnrichment(
        for taskID: UUID,
        rawInput: String,
        locale: Locale,
        timeZone: TimeZone,
        in context: ModelContext
    ) {
        Task { @MainActor [parser, authStore, syncService] in
            let parsed = await parser.parse(
                rawText: rawInput,
                locale: locale,
                timeZone: timeZone,
                installID: authStore.installID
            )

            let descriptor = FetchDescriptor<TaskRecord>(
                predicate: #Predicate { task in
                    task.id == taskID
                }
            )

            guard let fetchedTasks = try? context.fetch(descriptor), let task = fetchedTasks.first else {
                return
            }

            // Only apply the AI-parsed title if the user hasn't already renamed the
            // task — updateTitle/updateTaskDetails flip parseState to .parsed, so a
            // still-.pending state means the instant title is untouched. Without this
            // guard, an immediate manual rename snapped back seconds later. (TD-08)
            if task.parseState == .pending {
                task.title = parsed.title
            }
            // Only apply AI-parsed date if user didn't manually set one in the composer
            let appliedNewDueDate: Bool
            if task.dueDate == nil, let parsedDate = parsed.dueDate {
                task.dueDate = parsedDate
                appliedNewDueDate = true
            } else {
                appliedNewDueDate = false
            }
            // Surface degraded parses in the log so we can investigate why remote NLP keeps
            // failing — the user's task still gets saved, just with the local fallback's
            // (often weaker) date extraction.
            if parsed.lowConfidence {
                AppLogger.shared.log(
                    "TaskCaptureService.queueEnrichment: low-confidence parse for task \(taskID) — remote NLP unavailable"
                )
            }
            task.parseState = .parsed
            task.updatedAt = .now
            task.syncState = .pendingUpload
            try? context.save()
            syncReminder(task, in: context)
            // Schedule notification if enrichment applied a new due date
            if appliedNewDueDate {
                scheduleNotificationIfNeeded(task)
            }

            // Quiet folder suggestion for unfiled captures — one shot, chip UX,
            // never moves anything itself. Runs BEFORE the sync enqueue: the
            // suggestion is local UX and must not wait on (or be lost to) a
            // slow/failed network round-trip. (Tasks UX overhaul, 2026-07-17.)
            if task.folder == nil {
                await suggestFolder(for: task, in: context)
            }

            let mutation = SyncMutation(action: .upsert, task: task.asPayload(), taskID: task.id)
            await syncService.enqueue([mutation], in: context)
        }
    }

    private func syncReminder(_ task: TaskRecord, in context: ModelContext) {
        guard remindersSyncState.isEnabled else { return }
        guard remindersSyncState.direction != .fromReminders else { return }
        remindersSyncService.upsert(task, in: context)
    }

    private func deleteReminder(identifier: String?) {
        guard remindersSyncState.isEnabled else { return }
        guard remindersSyncState.direction != .fromReminders else { return }
        guard let identifier else { return }
        remindersSyncService.delete(identifier: identifier)
    }

    /// Schedule a local notification for a task if it has a due date and reminders are enabled.
    private func scheduleNotificationIfNeeded(_ task: TaskRecord) {
        guard taskRemindersEnabled, let dueDate = task.dueDate, !task.completed else { return }
        notificationService?.scheduleTaskReminder(
            taskID: task.id.uuidString,
            title: task.title,
            dueDate: dueDate
        )
    }

    // MARK: - Folder summary & contents

    /// Fetch the cards-ready summary from the backend and update each FolderRecord's
    /// cached count / breakdown / recent items so `FolderCardView` renders instantly.
    func fetchFolderSummary(in context: ModelContext) async {
        do {
            let response: FolderSummaryResponse = try await apiClient.trpcQuery("folders.summary")
            let localFolders = (try? context.fetch(FetchDescriptor<FolderRecord>())) ?? []
            // UUID keys, not uuidString — server ids are lowercase, uuidString is
            // UPPERCASE, so string-keyed lookups never matched (empty folder cards).
            let byID = Dictionary(uniqueKeysWithValues: localFolders.map { ($0.id, $0) })

            for remote in response.folders {
                guard let remoteID = UUID(uuidString: remote.folder.id),
                      let local = byID[remoteID] else { continue }
                local.cachedItemCount = remote.itemCount
                local.setBreakdown(FolderTypeBreakdown(
                    tasks: remote.breakdown.tasks,
                    chats: remote.breakdown.chats,
                    emails: remote.breakdown.emails,
                    events: remote.breakdown.events,
                    docs: remote.breakdown.docs
                ))
                local.setRecentItems(remote.recentItems.map {
                    FolderRecentItem(
                        type: $0.type,
                        id: $0.id,
                        title: $0.title,
                        subtitle: $0.subtitle,
                        sortAt: $0.sortAt
                    )
                })
            }
            try? context.save()
        } catch {
            // Best-effort — cards keep showing previous cached values.
        }
    }

    /// Result of `fetchFolderContents`. `remoteFetchFailed` lets the caller distinguish
    /// a genuinely empty folder from one where the backend call failed and we fell back
    /// to local-only data.
    struct FolderContentsResult {
        let items: [FolderContentItem]
        let remoteFetchFailed: Bool
    }

    /// Fetch the full mixed-type contents for a single folder from the backend.
    /// Tasks are resolved against local SwiftData so users get the live TaskRecord
    /// (with completion state, etc.). Chats / emails / events / docs are returned
    /// as lightweight value types since their full data lives elsewhere.
    func fetchFolderContents(_ folder: FolderRecord, in context: ModelContext) async -> FolderContentsResult {
        struct ContentsInput: Encodable {
            let folderId: String
            let limit: Int
        }

        let allTasks = (try? context.fetch(FetchDescriptor<TaskRecord>())) ?? []
        // UUID keys, not uuidString — server ids are lowercase, uuidString is
        // UPPERCASE, so string-keyed lookups never resolved remote task rows.
        let tasksByID = Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) })

        var items: [FolderContentItem] = []
        var seenIDs = Set<String>()
        var remoteFetchFailed = false

        do {
            let response: FolderContentsResponse = try await apiClient.trpcQuery(
                "folders.listContents",
                input: ContentsInput(folderId: folder.id.uuidString, limit: 200)
            )

            for raw in response.items {
                switch raw.type {
                case "task":
                    if let rawUUID = UUID(uuidString: raw.id), let task = tasksByID[rawUUID] {
                        items.append(.task(task))
                        // Lowercased so it matches the local-task dedup key below
                        // regardless of server id casing.
                        seenIDs.insert("task-\(raw.id.lowercased())")
                    }
                case "chat":
                    items.append(.chat(id: raw.id, title: raw.title, updatedAt: raw.sortAt))
                    seenIDs.insert("chat-\(raw.id)")
                case "email":
                    items.append(.email(threadId: raw.id, subject: raw.title, sender: raw.subtitle, date: raw.sortAt))
                    seenIDs.insert("email-\(raw.id)")
                case "event":
                    items.append(.event(eventId: raw.id, title: raw.title, start: raw.sortAt))
                    seenIDs.insert("event-\(raw.id)")
                case "doc":
                    items.append(.doc(docId: raw.id, title: raw.title, updatedAt: raw.sortAt))
                    seenIDs.insert("doc-\(raw.id)")
                default:
                    break
                }
            }
        } catch {
            // Backend unavailable — fall through to local-only data below.
            remoteFetchFailed = true
        }

        // Merge any locally-saved items not yet reflected in the backend response.
        // This makes newly-added items appear immediately without waiting for sync.
        let folderID = folder.id
        let localFolderItems = (try? context.fetch(FetchDescriptor<FolderItemRecord>())) ?? []
        for record in localFolderItems where record.folder?.id == folderID {
            let key = "\(record.itemType)-\(record.itemId)"
            guard !seenIDs.contains(key) else { continue }
            switch record.itemType {
            case "email":
                items.append(.email(
                    threadId: record.itemId,
                    subject: record.titleCache ?? "",
                    sender: record.subtitleCache,
                    date: record.createdAt
                ))
            case "event":
                items.append(.event(eventId: record.itemId, title: record.titleCache ?? "", start: record.createdAt))
            case "doc":
                items.append(.doc(docId: record.itemId, title: record.titleCache ?? "", updatedAt: record.createdAt))
            default:
                break
            }
            seenIDs.insert(key)
        }

        // Include local tasks assigned to this folder but not yet visible on backend.
        for task in allTasks where task.folder?.id == folderID {
            let key = "task-\(task.id.uuidString.lowercased())"
            if !seenIDs.contains(key) {
                items.append(.task(task))
                seenIDs.insert(key)
            }
        }

        return FolderContentsResult(
            items: items.sorted { $0.sortDate > $1.sortDate },
            remoteFetchFailed: remoteFetchFailed
        )
    }

    // MARK: - Folder items (emails / events / docs)

    /// Bookmark an external entity (Gmail thread, calendar event, doc) into a folder.
    /// Tasks and chats use their own folder column instead.
    func addItemToFolder(
        kind: FolderItemKind,
        itemId: String,
        title: String?,
        subtitle: String?,
        folder: FolderRecord,
        in context: ModelContext
    ) {
        guard kind == .email || kind == .event || kind == .doc else { return }

        let folderID = folder.id
        let itemType = kind.rawValue
        let existingItems = (try? context.fetch(FetchDescriptor<FolderItemRecord>())) ?? []
        let alreadyExists = existingItems.contains {
            $0.folder?.id == folderID && $0.itemType == itemType && $0.itemId == itemId
        }
        guard !alreadyExists else { return }

        // Local mirror for offline browsing.
        let item = FolderItemRecord(
            folder: folder,
            itemType: itemType,
            itemId: itemId,
            titleCache: title,
            subtitleCache: subtitle,
            position: 0,
            createdAt: .now
        )
        context.insert(item)
        folder.cachedItemCount += 1
        folder.updatedAt = .now
        try? context.save()

        // Optimistic count was bumped above. Roll back on sync failure so the local
        // mirror doesn't drift from the server over time. fetchFolderSummary still
        // reconciles eventually, but rolling back keeps the UI honest in the meantime.
        Task { @MainActor [weak self, folder, item, title, subtitle] in
            guard let self else { return }
            do {
                try await syncFolderItemAdd(
                    folderID: folder.id.uuidString,
                    itemType: itemType,
                    itemId: itemId,
                    title: title,
                    subtitle: subtitle
                )
            } catch {
                // Roll back BOTH halves of the optimistic insert — the count AND the
                // FolderItemRecord row. Decrementing only the count left a phantom row
                // the server never learned about. (TD-21b)
                if !item.isDeleted {
                    context.delete(item)
                }
                folder.cachedItemCount = max(0, folder.cachedItemCount - 1)
                try? context.save()
            }
        }
    }

    func removeItemFromFolder(
        kind: FolderItemKind,
        itemId: String,
        folder: FolderRecord,
        in context: ModelContext
    ) {
        guard kind == .email || kind == .event || kind == .doc else { return }

        let typeRaw = kind.rawValue
        let folderID = folder.id
        let allItems = (try? context.fetch(FetchDescriptor<FolderItemRecord>())) ?? []
        let matching = allItems.filter {
            $0.folder?.id == folderID && $0.itemType == typeRaw && $0.itemId == itemId
        }
        for item in matching {
            context.delete(item)
        }
        if !matching.isEmpty {
            folder.cachedItemCount = max(0, folder.cachedItemCount - matching.count)
            folder.updatedAt = .now
        }
        try? context.save()

        Task {
            await syncFolderItemRemove(
                folderID: folder.id.uuidString,
                itemType: typeRaw,
                itemId: itemId
            )
        }
    }

    private func syncFolderItemAdd(
        folderID: String,
        itemType: String,
        itemId: String,
        title: String?,
        subtitle: String?
    ) async throws {
        struct Metadata: Encodable {
            let title: String?
            let subtitle: String?
        }
        struct AddInput: Encodable {
            let folderId: String
            let itemType: String
            let itemId: String
            let metadata: Metadata?
        }

        let metadata: Metadata? = (title != nil || subtitle != nil)
            ? Metadata(title: title, subtitle: subtitle)
            : nil

        let _: EmptyResponse = try await apiClient.trpcMutation(
            "folders.addItem",
            input: AddInput(
                folderId: folderID,
                itemType: itemType,
                itemId: itemId,
                metadata: metadata
            )
        )
    }

    private func syncFolderItemRemove(folderID: String, itemType: String, itemId: String) async {
        struct RemoveInput: Encodable {
            let folderId: String
            let itemType: String
            let itemId: String
        }

        do {
            let _: EmptyResponse = try await apiClient.trpcMutation(
                "folders.removeItem",
                input: RemoveInput(folderId: folderID, itemType: itemType, itemId: itemId)
            )
        } catch {
            // Best-effort sync only.
        }
    }
}

// MARK: - Folder remote DTOs

struct RemoteFolder: Decodable {
    let id: String
    let name: String
    let color: String?
    let icon: String?
    let position: Int?
    let createdAt: Date
    let updatedAt: Date?
}

private struct RemoteFolderBreakdown: Decodable {
    let tasks: Int
    let chats: Int
    let emails: Int
    let events: Int
    let docs: Int
}

private struct RemoteFolderRecentItem: Decodable {
    let type: String
    let id: String
    let title: String
    let subtitle: String?
    let sortAt: Date
}

private struct RemoteFolderSummaryEntry: Decodable {
    let folder: RemoteFolder
    let itemCount: Int
    let breakdown: RemoteFolderBreakdown
    let recentItems: [RemoteFolderRecentItem]
}

private struct FolderSummaryResponse: Decodable {
    let folders: [RemoteFolderSummaryEntry]
}

private struct FolderContentsItem: Decodable {
    let type: String
    let id: String
    let title: String
    let subtitle: String?
    let sortAt: Date
}

private struct FolderContentsResponse: Decodable {
    let items: [FolderContentsItem]
    let folder: RemoteFolder
}
