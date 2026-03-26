import Foundation

// MARK: - AIChatMessage

/// A single message in the AI chat conversation.
struct AIChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id: UUID
    var role: Role
    /// Text content — grows token-by-token during streaming
    var content: String
    /// True while the assistant response is still streaming in
    var isStreaming: Bool
    /// Task mutations the AI requested (create / update / delete)
    var taskMutations: [AIChatTaskMutation]

    init(
        id: UUID = UUID(),
        role: Role,
        content: String = "",
        isStreaming: Bool = false,
        taskMutations: [AIChatTaskMutation] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
        self.taskMutations = taskMutations
    }
}

// MARK: - AIChatTaskMutation

/// Describes a task operation the AI wants to perform.
struct AIChatTaskMutation: Identifiable {
    enum Action: String, Codable {
        case create
        case update
        case delete
    }

    let id: UUID
    let action: Action
    /// Task ID (required for update/delete)
    var taskID: UUID?
    var title: String?
    var dueDate: Date?
    var folderName: String?
    var priority: String?
    var status: String?
    /// True once this mutation has been applied to the SwiftData store
    var applied: Bool

    init(
        id: UUID = UUID(),
        action: Action,
        taskID: UUID? = nil,
        title: String? = nil,
        dueDate: Date? = nil,
        folderName: String? = nil,
        priority: String? = nil,
        status: String? = nil
    ) {
        self.id = id
        self.action = action
        self.taskID = taskID
        self.title = title
        self.dueDate = dueDate
        self.folderName = folderName
        self.priority = priority
        self.status = status
        self.applied = false
    }
}
