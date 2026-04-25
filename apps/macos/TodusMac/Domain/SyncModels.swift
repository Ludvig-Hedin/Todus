import Foundation

/// Controls the direction of sync between Todus and Apple Reminders.
enum RemindersSyncDirection: String, CaseIterable, Identifiable, Sendable {
    case twoWay
    case toReminders
    case fromReminders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .twoWay: return "Two-way"
        case .toReminders: return "To Reminders"
        case .fromReminders: return "From Reminders"
        }
    }

    var subtitle: String {
        switch self {
        case .twoWay: return "Changes sync both ways"
        case .toReminders: return "Todus tasks push to Reminders"
        case .fromReminders: return "Reminders pull into Todus"
        }
    }

    var icon: String {
        switch self {
        case .twoWay: return "arrow.left.arrow.right"
        case .toReminders: return "arrow.right"
        case .fromReminders: return "arrow.left"
        }
    }
}

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
