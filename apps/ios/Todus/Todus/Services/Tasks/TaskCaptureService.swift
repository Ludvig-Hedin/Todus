import Foundation
import SwiftData

@MainActor
final class TaskCaptureService {
    private let parser: TaskParsingService
    private let syncService: SyncService
    private let authStore: AuthSessionStore
    private let remindersSyncService: AppleRemindersSyncService
    private let remindersSyncState: RemindersSyncState

    init(
        parser: TaskParsingService,
        syncService: SyncService,
        authStore: AuthSessionStore,
        remindersSyncService: AppleRemindersSyncService,
        remindersSyncState: RemindersSyncState
    ) {
        self.parser = parser
        self.syncService = syncService
        self.authStore = authStore
        self.remindersSyncService = remindersSyncService
        self.remindersSyncState = remindersSyncState
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

        var mutations: [SyncMutation] = []

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
            mutations.append(SyncMutation(action: .upsert, task: task.asPayload(), taskID: task.id))
            queueEnrichment(for: task.id, rawInput: line, locale: locale, timeZone: timeZone, in: context)
        }

        try? context.save()

        Task { @MainActor [syncService] in
            await syncService.enqueue(mutations, in: context)
        }
    }

    func toggleCompletion(_ task: TaskRecord, in context: ModelContext) {
        setStatus(task, status: task.completed ? .todo : .done, in: context)
    }

    func setStatus(_ task: TaskRecord, status: TaskStatus, in context: ModelContext) {
        task.status = status
        task.completed = status == .done
        task.updatedAt = .now
        task.syncState = .pendingUpload
        persist(task: task, in: context)
        syncReminder(task, in: context)
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
        task.completed = status == .done
        task.priority = priority
        task.dueDate = dueDate
        task.folder = folder
        task.attachmentNames = attachmentNames
        task.updatedAt = .now
        task.parseState = .parsed
        task.syncState = .pendingUpload
        persist(task: task, in: context)
        syncReminder(task, in: context)
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
        deleteReminder(task)
        context.delete(task)
        try? context.save()

        Task { @MainActor [syncService] in
            await syncService.enqueue([mutation], in: context)
        }
    }

    func clearCompletedTasks(filteredBy folderID: UUID?, in context: ModelContext) {
        let tasks = ((try? context.fetch(FetchDescriptor<TaskRecord>())) ?? []).filter { task in
            task.status == .done && (folderID == nil || task.folderID == folderID)
        }

        guard !tasks.isEmpty else { return }

        let mutations = tasks.map { task in
            SyncMutation(action: .delete, task: nil, taskID: task.id)
        }

        for task in tasks {
            deleteReminder(task)
            context.delete(task)
        }

        try? context.save()

        Task { @MainActor [syncService] in
            await syncService.enqueue(mutations, in: context)
        }
    }

    func createFolder(named name: String, in context: ModelContext) -> FolderRecord? {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return nil }

        let existing = (try? context.fetch(FetchDescriptor<FolderRecord>())) ?? []

        if let existingFolder = existing.first(where: { $0.name.compare(cleanedName, options: .caseInsensitive) == .orderedSame }) {
            return existingFolder
        }

        let folder = FolderRecord(name: cleanedName)
        context.insert(folder)
        try? context.save()
        return folder
    }

    nonisolated static func splitInputLines(_ rawText: String) -> [String] {
        rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    nonisolated static func instantTitle(from rawText: String) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New task" : trimmed
    }

    private func persist(task: TaskRecord, in context: ModelContext) {
        try? context.save()
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

            task.title = parsed.title
            // Only apply AI-parsed date if user didn't manually set one in the composer
            if task.dueDate == nil, let parsedDate = parsed.dueDate {
                task.dueDate = parsedDate
            }
            task.parseState = .parsed
            task.updatedAt = .now
            task.syncState = .pendingUpload
            try? context.save()
            syncReminder(task, in: context)

            let mutation = SyncMutation(action: .upsert, task: task.asPayload(), taskID: task.id)
            await syncService.enqueue([mutation], in: context)
        }
    }

    private func syncReminder(_ task: TaskRecord, in context: ModelContext) {
        guard remindersSyncState.isEnabled else { return }
        remindersSyncService.upsert(task, in: context)
    }

    private func deleteReminder(_ task: TaskRecord) {
        guard remindersSyncState.isEnabled else { return }
        remindersSyncService.delete(task)
    }
}
