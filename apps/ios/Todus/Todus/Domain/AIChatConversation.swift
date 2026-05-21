import Foundation

// MARK: - AIChatConversation

/// A persisted chat session loaded from or saved to history.
/// Uses a lightweight Codable struct to avoid coupling to SwiftData.
struct AIChatConversation: Identifiable, Codable {
    let id: UUID
    var title: String
    let createdAt: Date
    /// Local timestamp updated whenever the conversation is mutated locally.
    /// Used to skip overwriting fresher local copies with stale remote payloads
    /// during background sync.
    var updatedAt: Date
    var folderID: UUID?

    /// Flat array of saved messages with enough metadata to preserve follow-up references
    /// when a saved conversation is later reopened.
    var messages: [SavedMessage]

    init(
        id: UUID,
        title: String,
        createdAt: Date,
        updatedAt: Date? = nil,
        folderID: UUID? = nil,
        messages: [SavedMessage]
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.folderID = folderID
        self.messages = messages
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, createdAt, updatedAt, folderID, messages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        // Older persisted copies don't carry `updatedAt` — default to createdAt
        // so the sync-merge comparison treats them as "not newer than remote".
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
        messages = try container.decode([SavedMessage].self, forKey: .messages)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(folderID, forKey: .folderID)
        try container.encode(messages, forKey: .messages)
    }

    struct SavedMessage: Codable {
        let role: String      // "user" | "assistant"
        let content: String
        let mentions: [RichInputMentionRef]
        let attachmentFileNames: [String]

        init(
            role: String,
            content: String,
            mentions: [RichInputMentionRef] = [],
            attachmentFileNames: [String] = []
        ) {
            self.role = role
            self.content = content
            self.mentions = mentions
            self.attachmentFileNames = attachmentFileNames
        }

        private enum CodingKeys: String, CodingKey {
            case role
            case content
            case mentions
            case attachmentFileNames
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            role = try container.decode(String.self, forKey: .role)
            content = try container.decode(String.self, forKey: .content)
            mentions = try container.decodeIfPresent([RichInputMentionRef].self, forKey: .mentions) ?? []
            attachmentFileNames = try container.decodeIfPresent([String].self, forKey: .attachmentFileNames) ?? []
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(role, forKey: .role)
            try container.encode(content, forKey: .content)
            try container.encode(mentions, forKey: .mentions)
            try container.encode(attachmentFileNames, forKey: .attachmentFileNames)
        }
    }
}
