import Foundation

/// User-created email signature, persisted as JSON in UserDefaults.
/// Each signature has a name (shown in lists) and body (appended to emails).
struct EmailSignature: Codable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var body: String

    init(id: UUID = UUID(), name: String, body: String) {
        self.id = id
        self.name = name
        self.body = body
    }
}

/// Lightweight DTOs for email data from the backend API.
/// These mirror the TRPC response shapes from the Cloudflare Workers backend.

struct EmailSender: Codable, Identifiable, Hashable {
    var id: String { email }
    let name: String
    let email: String

    /// Backend sends `name` as optional — default to email if nil
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.email = try container.decode(String.self, forKey: .email)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? self.email
    }

    init(name: String, email: String) {
        self.name = name
        self.email = email
    }

    private enum CodingKeys: String, CodingKey {
        case name, email
    }
}

struct EmailThread: Codable, Identifiable, Equatable {
    let id: String
    let subject: String
    let snippet: String
    let from: EmailSender
    let date: Date
    let unread: Bool
    let messageCount: Int
    let labels: [String]
}

/// Maps from backend ParsedMessage JSON to our EmailMessage model.
/// Backend field names differ from our model:
///   - `sender` → `from`
///   - `receivedOn` (ISO date string) → `date`
///   - `decodedBody` → `body` (HTML content)
///   - `title` → `snippet` (used as plainText fallback)
struct EmailMessage: Decodable, Identifiable {
    let id: String
    let threadId: String
    let from: EmailSender
    let to: [EmailSender]
    let cc: [EmailSender]?
    let subject: String
    let body: String        // HTML body (from decodedBody)
    let plainText: String?  // Plain text fallback (from title/snippet)
    let date: Date
    let attachments: [EmailAttachment]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.threadId = try container.decodeIfPresent(String.self, forKey: .threadId) ?? ""
        // Backend uses "sender" not "from"
        self.from = try container.decode(EmailSender.self, forKey: .sender)
        self.to = try container.decodeIfPresent([EmailSender].self, forKey: .to) ?? []
        self.cc = try container.decodeIfPresent([EmailSender].self, forKey: .cc)
        self.subject = try container.decodeIfPresent(String.self, forKey: .subject) ?? "(no subject)"
        // HTML body from decodedBody, fallback to body
        let decodedBody = try container.decodeIfPresent(String.self, forKey: .decodedBody)
        let rawBody = try container.decodeIfPresent(String.self, forKey: .body)
        self.body = decodedBody ?? rawBody ?? ""
        // Snippet/title as plainText fallback
        self.plainText = try container.decodeIfPresent(String.self, forKey: .title)
        // Date from receivedOn ISO string — use distantPast as fallback so
        // unparseable dates sort to the bottom rather than appearing as "now"
        let receivedOn = try container.decodeIfPresent(String.self, forKey: .receivedOn) ?? ""
        if let parsed = Self.parseDate(receivedOn) {
            self.date = parsed
        } else {
            if !receivedOn.isEmpty {
                print("[EmailMessage] Failed to parse date string: \(receivedOn)")
            }
            self.date = .distantPast
        }
        // Attachments
        self.attachments = try container.decodeIfPresent([EmailAttachment].self, forKey: .attachments)
    }

    // Cached formatters — `parseDate` runs once per message decode, so a 50-thread
    // batch with multi-message threads previously allocated hundreds of formatters
    // (each ~expensive) on the decode thread. ISO8601DateFormatter / DateFormatter
    // are thread-safe for parsing once configured, so sharing them is safe.
    // `nonisolated(unsafe)`: ISO8601DateFormatter / DateFormatter are thread-safe
    // for parsing once their config is set (Apple docs), but aren't `Sendable`, so
    // Swift 6 strict concurrency rejects a plain `static let`. Same pattern the
    // codebase already uses for shared formatters/stubs.
    private nonisolated(unsafe) static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private nonisolated(unsafe) static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let rfcFormatters: [DateFormatter] = {
        ["EEE, dd MMM yyyy HH:mm:ss Z", "dd MMM yyyy HH:mm:ss Z", "yyyy-MM-dd'T'HH:mm:ss.SSSZ"].map { fmt in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = fmt
            return f
        }
    }()

    /// Parse various date formats the backend might send. Uses cached formatters.
    private static func parseDate(_ string: String) -> Date? {
        if let date = isoFractional.date(from: string) { return date }
        if let date = isoPlain.date(from: string) { return date }
        // Try RFC 2822 style dates (e.g. "Mon, 24 Mar 2025 10:30:00 +0000")
        for formatter in rfcFormatters {
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, threadId, sender, to, cc, subject, body, decodedBody, title, receivedOn, attachments
    }
}

struct EmailAttachment: Decodable, Identifiable {
    let id: String
    let filename: String
    let mimeType: String
    let size: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Backend uses "attachmentId" not "id"
        let filename = try container.decodeIfPresent(String.self, forKey: .filename) ?? ""
        let size = try container.decodeIfPresent(Int.self, forKey: .size) ?? 0
        // Use deterministic fallback ID based on filename+size to avoid unstable random UUIDs
        self.id = try container.decodeIfPresent(String.self, forKey: .attachmentId)
            ?? container.decodeIfPresent(String.self, forKey: .id)
            ?? "attachment-\(filename)-\(size)"
        self.filename = filename
        self.mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType) ?? ""
        self.size = size
    }

    private enum CodingKeys: String, CodingKey {
        case id, attachmentId, filename, mimeType, size
    }
}

/// Used when composing/sending an email
struct EmailDraft {
    var to: [String] = []
    var cc: [String] = []
    var bcc: [String] = []
    var subject: String = ""
    var body: String = ""
    var replyToThreadId: String?
    var replyToMessageId: String?
    /// Optional connection ID to send from a specific account (uses default if nil)
    var fromConnectionId: String?
    /// True when this draft is a Forward — the backend uses `originalMessage` to
    /// build the quoted block instead of sending it inline in `body`.
    var isForward: Bool = false
    /// HTML/plaintext of the message being forwarded. Backend wraps it as the
    /// quoted "----- Forwarded message -----" block.
    var originalMessage: String?
}
