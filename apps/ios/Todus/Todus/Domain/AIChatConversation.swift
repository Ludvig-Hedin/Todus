import Foundation

// MARK: - AIChatConversation

/// A persisted chat session loaded from or saved to history.
/// Uses a lightweight Codable struct to avoid coupling to SwiftData.
struct AIChatConversation: Identifiable, Codable {
    let id: UUID
    var title: String
    let createdAt: Date

    /// Flat array of saved messages with enough metadata to preserve follow-up references
    /// when a saved conversation is later reopened.
    var messages: [SavedMessage]

    struct SavedMessage: Codable {
        let role: String      // "user" | "assistant"
        let content: String
        let mentions: [RichInputMentionRef]

        init(
            role: String,
            content: String,
            mentions: [RichInputMentionRef] = []
        ) {
            self.role = role
            self.content = content
            self.mentions = mentions
        }

        private enum CodingKeys: String, CodingKey {
            case role
            case content
            case mentions
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            role = try container.decode(String.self, forKey: .role)
            content = try container.decode(String.self, forKey: .content)
            mentions = try container.decodeIfPresent([RichInputMentionRef].self, forKey: .mentions) ?? []
        }
    }
}
