import Foundation
import SwiftData

/// Single checklist item embedded in a `TaskRecord`. Persisted as JSON in
/// `TaskRecord.checklistItemsData` so this can evolve without a SwiftData migration.
struct ChecklistItem: Codable, Identifiable, Sendable, Hashable {
    var id: UUID
    var title: String
    var completed: Bool
    var order: Int

    init(id: UUID = UUID(), title: String, completed: Bool = false, order: Int = 0) {
        self.id = id
        self.title = title
        self.completed = completed
        self.order = order
    }
}

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
    /// Gmail thread ID — links this task to an email conversation (nullable)
    var emailThreadId: String?
    /// EKEvent identifier — links this task to a calendar event (nullable)
    var eventId: String?
    var createdAt: Date
    var updatedAt: Date
    var dueDate: Date?
    /// Recurrence rule. Either a simple keyword (`"daily" | "weekly" | "monthly" | "yearly"`)
    /// or an RFC 5545 RRULE string. `nil` means non-recurring. Matches the iOS shape.
    var recurrenceRule: String?
    /// JSON-encoded `[ChecklistItem]`. Access via `checklistItems` accessor.
    var checklistItemsData: Data?
    /// JSON-encoded `[String]` of attachment file paths (relative to
    /// `Application Support/TaskAttachments/<taskId>/`). Access via `attachmentPaths`.
    var attachmentPathsData: Data?
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

    /// JSON-decoded view of `checklistItemsData`. Setter re-encodes; an empty
    /// array is stored as `nil` to keep the underlying column tidy. Decode
    /// failures fall back to an empty array so a malformed blob never crashes
    /// the UI — the next write will overwrite it cleanly.
    var checklistItems: [ChecklistItem] {
        get {
            guard let data = checklistItemsData, !data.isEmpty else { return [] }
            return (try? JSONDecoder().decode([ChecklistItem].self, from: data)) ?? []
        }
        set {
            if newValue.isEmpty {
                checklistItemsData = nil
            } else {
                checklistItemsData = try? JSONEncoder().encode(newValue)
            }
        }
    }

    /// JSON-decoded view of `attachmentPathsData`. Empty array stored as `nil`.
    var attachmentPaths: [String] {
        get {
            guard let data = attachmentPathsData, !data.isEmpty else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            if newValue.isEmpty {
                attachmentPathsData = nil
            } else {
                attachmentPathsData = try? JSONEncoder().encode(newValue)
            }
        }
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
