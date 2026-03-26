import Foundation

/// Lightweight DTOs for email data from the backend API.
/// These mirror the TRPC response shapes from the Cloudflare Workers backend.

struct EmailSender: Codable, Identifiable, Hashable {
    var id: String { email }
    let name: String
    let email: String
}

struct EmailThread: Codable, Identifiable {
    let id: String
    let subject: String
    let snippet: String
    let from: EmailSender
    let date: Date
    let unread: Bool
    let messageCount: Int
    let labels: [String]
}

struct EmailMessage: Codable, Identifiable {
    let id: String
    let threadId: String
    let from: EmailSender
    let to: [EmailSender]
    let cc: [EmailSender]?
    let subject: String
    let body: String        // HTML body
    let plainText: String?  // Plain text fallback
    let date: Date
    let attachments: [EmailAttachment]?
}

struct EmailAttachment: Codable, Identifiable {
    let id: String
    let filename: String
    let mimeType: String
    let size: Int
}

/// Used when composing/sending an email
struct EmailDraft {
    var to: [String] = []
    var cc: [String] = []
    var subject: String = ""
    var body: String = ""
    var replyToThreadId: String?
    var replyToMessageId: String?
}
