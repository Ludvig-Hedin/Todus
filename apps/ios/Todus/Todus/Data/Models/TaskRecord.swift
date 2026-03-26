import Foundation
import SwiftData

@Model
final class TaskRecord: Identifiable {
    @Attribute(.unique) var id: UUID
    var rawInput: String
    var title: String
    var taskDescription: String
    var completed: Bool
    var statusRawValue: String
    var priorityRawValue: String
    var attachmentNamesRawValue: String
    var reminderIdentifier: String?
    var createdAt: Date
    var updatedAt: Date
    var dueDate: Date?
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
        folder: FolderRecord? = nil,
        parseState: ParseState = .pending,
        syncState: SyncState = .pendingUpload
    ) {
        self.id = id
        self.rawInput = rawInput
        self.title = title
        self.taskDescription = taskDescription
        self.completed = completed
        self.statusRawValue = status.rawValue
        self.priorityRawValue = priority.rawValue
        self.attachmentNamesRawValue = attachmentNames.joined(separator: "\n")
        self.reminderIdentifier = reminderIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.dueDate = dueDate
        self.folder = folder
        self.parseStateRawValue = parseState.rawValue
        self.syncStateRawValue = syncState.rawValue
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRawValue) ?? .todo }
        set {
            statusRawValue = newValue.rawValue
            completed = newValue == .done
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
            completed: completed,
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
