import Foundation
import SwiftData

@Model
final class TaskRecord: Identifiable {
    @Attribute(.unique) var id: UUID
    var rawInput: String
    var title: String
    var taskDescription: String
    /// Kept in sync with `status` via `status` setter and `didSet` so it cannot drift from `completedAt` / `statusRawValue`.
    var completed: Bool = false {
        didSet {
            if oldValue == completed { return }
            if completed {
                if status != .done { status = .done }
            } else if status == .done {
                status = .todo
            }
        }
    }
    var statusRawValue: String
    var priorityRawValue: String
    var attachmentNamesRawValue: String
    var reminderIdentifier: String?
    /// Gmail thread ID — links this task to an email conversation (nullable)
    var emailThreadId: String?
    /// EKEvent identifier — links this task to a calendar event (nullable)
    var eventId: String?
    var createdAt: Date
    var updatedAt: Date
    var dueDate: Date?
    /// Set when the task is marked done; used to keep the row in the main list for a few seconds before the “Recently completed” section. Cleared when uncompleted.
    var completedAt: Date?
    var parseStateRawValue: String
    var syncStateRawValue: String
    var folder: FolderRecord?

    init(
        id: UUID = UUID(),
        rawInput: String,
        title: String,
        taskDescription: String = "",
        completed: Bool = false,
        status: TaskStatus = .todo,
        priority: AppTaskPriority = .none,
        attachmentNames: [String] = [],
        reminderIdentifier: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        dueDate: Date? = nil,
        completedAt: Date? = nil,
        folder: FolderRecord? = nil,
        parseState: ParseState = .pending,
        syncState: SyncState = .pendingUpload
    ) {
        self.id = id
        self.rawInput = rawInput
        self.title = title
        self.taskDescription = taskDescription
        let initialStatus: TaskStatus = {
            if completed { return .done }
            if status == .done { return .todo }
            return status
        }()
        self.statusRawValue = initialStatus.rawValue
        self.completed = initialStatus == .done
        self.priorityRawValue = priority.rawValue
        self.attachmentNamesRawValue = attachmentNames.joined(separator: "\n")
        self.reminderIdentifier = reminderIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.dueDate = dueDate
        self.completedAt = initialStatus == .done ? (completedAt ?? updatedAt) : nil
        self.folder = folder
        self.parseStateRawValue = parseState.rawValue
        self.syncStateRawValue = syncState.rawValue
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRawValue) ?? .todo }
        set {
            let next = newValue
            statusRawValue = next.rawValue
            completed = next == .done
            if next == .done {
                if completedAt == nil { completedAt = .now }
            } else {
                completedAt = nil
            }
        }
    }

    var parseState: ParseState {
        get { ParseState(rawValue: parseStateRawValue) ?? .raw }
        set { parseStateRawValue = newValue.rawValue }
    }

    var priority: AppTaskPriority {
        get { AppTaskPriority(rawValue: priorityRawValue) ?? .none }
        set { priorityRawValue = newValue.rawValue }
    }

    var attachmentNames: [String] {
        get {
            attachmentNamesRawValue
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            attachmentNamesRawValue = newValue.joined(separator: "\n")
        }
    }

    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRawValue) ?? .localOnly }
        set { syncStateRawValue = newValue.rawValue }
    }

    var folderID: UUID? {
        folder?.id
    }

    func asPayload() -> TaskPayload {
        TaskPayload(
            id: id,
            rawInput: rawInput,
            title: title,
            taskDescription: taskDescription,
            completed: status == .done,
            status: status,
            priority: priority,
            attachmentNames: attachmentNames,
            reminderIdentifier: reminderIdentifier,
            createdAt: createdAt,
            updatedAt: updatedAt,
            dueDate: dueDate,
            folderID: folderID,
            parseState: parseState,
            syncState: syncState
        )
    }
}
