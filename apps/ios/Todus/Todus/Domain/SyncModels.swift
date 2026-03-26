import Foundation

enum SyncMutationAction: String, Codable, Sendable {
    case upsert
    case delete
}

struct SyncMutation: Codable, Sendable {
    let action: SyncMutationAction
    let task: TaskPayload?
    let taskID: UUID?

    var affectedTaskIDs: [UUID] {
        if let task {
            return [task.id]
        }

        if let taskID {
            return [taskID]
        }

        return []
    }
}

struct TaskPayload: Codable, Sendable {
    let id: UUID
    let rawInput: String
    let title: String
    let taskDescription: String
    let completed: Bool
    let status: TaskStatus
    let priority: AppTaskPriority
    let attachmentNames: [String]
    let reminderIdentifier: String?
    let createdAt: Date
    let updatedAt: Date
    let dueDate: Date?
    let folderID: UUID?
    let parseState: ParseState
    let syncState: SyncState
}
