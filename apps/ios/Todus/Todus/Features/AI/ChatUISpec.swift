import Foundation

// MARK: - JSON UI Spec Models
// These mirror the json-render spec format used by the web app.
// The AI generates a spec with a flat element map and a root ID.

/// Root container for a generative UI specification.
/// The `root` field points to the top-level element ID in `elements`.
struct ChatUISpec: Codable, Sendable {
    let root: String
    let elements: [String: UIElement]
}

/// A single element in the UI tree.
/// `type` determines which SwiftUI view to render.
/// `props` is a flexible dictionary of typed values.
/// `children` contains IDs of child elements (referencing siblings in the flat map).
struct UIElement: Codable, Sendable {
    let type: String
    let props: [String: ChatJSONValue]
    let children: [String]?

    init(type: String, props: [String: ChatJSONValue], children: [String]? = nil) {
        self.type = type
        self.props = props
        self.children = children
    }
}

// MARK: - ChatJSONValue
// Flexible enum for representing any JSON value in props.
// Handles string, number, bool, null, array, and object.

enum ChatJSONValue: Codable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([ChatJSONValue])
    case object([String: ChatJSONValue])

    // Convenience accessors
    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var numberValue: Double? {
        if case .number(let v) = self { return v }
        return nil
    }

    var intValue: Int? {
        if case .number(let v) = self { return Int(v) }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    var arrayValue: [ChatJSONValue]? {
        if case .array(let v) = self { return v }
        return nil
    }

    var objectValue: [String: ChatJSONValue]? {
        if case .object(let v) = self { return v }
        return nil
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    // MARK: Codable

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ChatJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: ChatJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "ChatJSONValue could not decode value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .null: try container.encodeNil()
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }
}

// MARK: - Strongly-Typed Card Props
// Optional convenience structs that can be initialized from ChatJSONValue props.
// These are used by the SwiftUI card views for type-safe access.

struct EmailCardProps {
    let threadId: String
    let sender: String
    let senderEmail: String
    let subject: String
    let snippet: String
    let receivedAt: String
    let isUnread: Bool
    let labels: [(name: String, color: String?)]

    init?(from props: [String: ChatJSONValue]) {
        guard let threadId = props["threadId"]?.stringValue,
              let sender = props["sender"]?.stringValue,
              let senderEmail = props["senderEmail"]?.stringValue,
              let subject = props["subject"]?.stringValue,
              let snippet = props["snippet"]?.stringValue,
              let receivedAt = props["receivedAt"]?.stringValue else {
            return nil
        }
        self.threadId = threadId
        self.sender = sender
        self.senderEmail = senderEmail
        self.subject = subject
        self.snippet = snippet
        self.receivedAt = receivedAt
        self.isUnread = props["isUnread"]?.boolValue ?? false
        self.labels = (props["labels"]?.arrayValue ?? []).compactMap { item in
            guard let obj = item.objectValue,
                  let name = obj["name"]?.stringValue else { return nil }
            return (name: name, color: obj["color"]?.stringValue)
        }
    }
}

struct TaskCardProps {
    let taskId: String
    let title: String
    let description: String?
    let status: String
    let priority: String
    let dueDate: String?
    let folderName: String?
    let emailThreadId: String?

    init?(from props: [String: ChatJSONValue]) {
        guard let taskId = props["taskId"]?.stringValue,
              let title = props["title"]?.stringValue,
              let status = props["status"]?.stringValue,
              let priority = props["priority"]?.stringValue else {
            return nil
        }
        self.taskId = taskId
        self.title = title
        self.description = props["description"]?.stringValue
        self.status = status
        self.priority = priority
        self.dueDate = props["dueDate"]?.stringValue
        self.folderName = props["folderName"]?.stringValue
        self.emailThreadId = props["emailThreadId"]?.stringValue
    }
}

struct CalendarEventCardProps {
    let eventId: String
    let title: String
    let start: String
    let end: String
    let location: String?
    let isAllDay: Bool
    let attendees: [(name: String?, email: String)]

    init?(from props: [String: ChatJSONValue]) {
        guard let eventId = props["eventId"]?.stringValue,
              let title = props["title"]?.stringValue,
              let start = props["start"]?.stringValue,
              let end = props["end"]?.stringValue else {
            return nil
        }
        self.eventId = eventId
        self.title = title
        self.start = start
        self.end = end
        self.location = props["location"]?.stringValue
        self.isAllDay = props["isAllDay"]?.boolValue ?? false
        self.attendees = (props["attendees"]?.arrayValue ?? []).compactMap { item in
            guard let obj = item.objectValue,
                  let email = obj["email"]?.stringValue else { return nil }
            return (name: obj["name"]?.stringValue, email: email)
        }
    }
}

struct NoteCardProps {
    let noteId: String
    let content: String
    let color: String?
    let isPinned: Bool
    let threadId: String?

    init?(from props: [String: ChatJSONValue]) {
        guard let noteId = props["noteId"]?.stringValue,
              let content = props["content"]?.stringValue else {
            return nil
        }
        self.noteId = noteId
        self.content = content
        self.color = props["color"]?.stringValue
        self.isPinned = props["isPinned"]?.boolValue ?? false
        self.threadId = props["threadId"]?.stringValue
    }
}

struct DraftCardProps {
    let draftId: String
    let subject: String
    let snippet: String
    let updatedAt: String?
    let to: [(name: String?, email: String)]

    init?(from props: [String: ChatJSONValue]) {
        guard let draftId = props["draftId"]?.stringValue,
              let subject = props["subject"]?.stringValue,
              let snippet = props["snippet"]?.stringValue else {
            return nil
        }
        self.draftId = draftId
        self.subject = subject
        self.snippet = snippet
        self.updatedAt = props["updatedAt"]?.stringValue
        self.to = (props["to"]?.arrayValue ?? []).compactMap { item in
            guard let obj = item.objectValue,
                  let email = obj["email"]?.stringValue else { return nil }
            return (name: obj["name"]?.stringValue, email: email)
        }
    }
}

struct LabelCardProps {
    let labelId: String
    let name: String
    let color: String?
    let count: Int?

    init?(from props: [String: ChatJSONValue]) {
        guard let labelId = props["labelId"]?.stringValue,
              let name = props["name"]?.stringValue else {
            return nil
        }
        self.labelId = labelId
        self.name = name
        self.color = props["color"]?.stringValue
        self.count = props["count"]?.intValue
    }
}

struct ContactCardProps {
    let name: String
    let email: String
    let avatarUrl: String?

    init?(from props: [String: ChatJSONValue]) {
        guard let name = props["name"]?.stringValue,
              let email = props["email"]?.stringValue else {
            return nil
        }
        self.name = name
        self.email = email
        self.avatarUrl = props["avatarUrl"]?.stringValue
    }
}

struct SearchResultCardProps {
    let query: String
    let resultCount: Int
    let summary: String?

    init?(from props: [String: ChatJSONValue]) {
        guard let query = props["query"]?.stringValue,
              let resultCount = props["resultCount"]?.intValue else {
            return nil
        }
        self.query = query
        self.resultCount = resultCount
        self.summary = props["summary"]?.stringValue
    }
}

// MARK: - Spec Parser

/// Extracts a ChatUISpec from a chat message's text content.
/// The AI embeds specs as ```ui-spec\n{...}\n``` code blocks.
struct ChatUISpecParser {
    /// Regex pattern matching ```ui-spec JSON blocks
    private static let specPattern = (try? NSRegularExpression(
        pattern: "```ui-spec\\n([\\s\\S]*?)\\n```",
        options: []
    )) ?? NSRegularExpression()

    struct ParseResult {
        let textBefore: String
        let spec: ChatUISpec?
        let textAfter: String
    }

    static func parse(_ content: String) -> ParseResult {
        let range = NSRange(content.startIndex..., in: content)
        guard let match = specPattern.firstMatch(in: content, options: [], range: range),
              let jsonRange = Range(match.range(at: 1), in: content) else {
            return ParseResult(textBefore: content, spec: nil, textAfter: "")
        }

        let jsonString = String(content[jsonRange])
        let spec: ChatUISpec? = {
            guard let data = jsonString.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(ChatUISpec.self, from: data)
        }()

        let matchRange = Range(match.range, in: content)!
        let textBefore = String(content[content.startIndex..<matchRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let textAfter = String(content[matchRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

        return ParseResult(textBefore: textBefore, spec: spec, textAfter: textAfter)
    }
}
