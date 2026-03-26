import Foundation

// MARK: - AIChatConversation

/// A persisted chat session loaded from or saved to history.
/// Uses a lightweight Codable struct to avoid coupling to SwiftData.
struct AIChatConversation: Identifiable, Codable {
    let id: UUID
    var title: String
    let createdAt: Date

    /// Flat array of saved messages — role + plain text only (mutations are already applied).
    var messages: [SavedMessage]

    struct SavedMessage: Codable {
        let role: String      // "user" | "assistant"
        let content: String
    }
}
