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

// MARK: - List Card Props

struct TaskListCardProps {
    let title: String?
    let tasks: [TaskCardProps]
    let followUp: String?
    let groupedThreshold: Int

    init?(from props: [String: ChatJSONValue]) {
        guard let tasksArray = props["tasks"]?.arrayValue else { return nil }
        self.title = props["title"]?.stringValue
        self.tasks = tasksArray.compactMap { item in
            guard let obj = item.objectValue else { return nil }
            return TaskCardProps(from: obj)
        }
        self.followUp = props["followUp"]?.stringValue
        self.groupedThreshold = props["groupedThreshold"]?.intValue ?? 4
    }
}

struct EmailListCardProps {
    let title: String?
    let emails: [EmailCardProps]
    let summary: String?

    init?(from props: [String: ChatJSONValue]) {
        guard let emailsArray = props["emails"]?.arrayValue else { return nil }
        self.title = props["title"]?.stringValue
        self.emails = emailsArray.compactMap { item in
            guard let obj = item.objectValue else { return nil }
            return EmailCardProps(from: obj)
        }
        self.summary = props["summary"]?.stringValue
    }
}

struct CalendarEventListCardProps {
    let title: String?
    let events: [CalendarEventCardProps]
    let summary: String?

    init?(from props: [String: ChatJSONValue]) {
        guard let eventsArray = props["events"]?.arrayValue else { return nil }
        self.title = props["title"]?.stringValue
        self.events = eventsArray.compactMap { item in
            guard let obj = item.objectValue else { return nil }
            return CalendarEventCardProps(from: obj)
        }
        self.summary = props["summary"]?.stringValue
    }
}

struct ContactListCardProps {
    let title: String?
    let contacts: [ContactCardProps]

    init?(from props: [String: ChatJSONValue]) {
        guard let contactsArray = props["contacts"]?.arrayValue else { return nil }
        self.title = props["title"]?.stringValue
        self.contacts = contactsArray.compactMap { item in
            guard let obj = item.objectValue else { return nil }
            return ContactCardProps(from: obj)
        }
    }
}

// MARK: - Utility Card Props

struct CopyableTextCardProps {
    let label: String
    let content: String

    init?(from props: [String: ChatJSONValue]) {
        guard let label = props["label"]?.stringValue,
              let content = props["content"]?.stringValue else { return nil }
        self.label = label
        self.content = content
    }
}

struct InlineComposeCardProps {
    let draftId: String
    let to: [(name: String?, email: String)]
    let cc: [(name: String?, email: String)]
    let bcc: [(name: String?, email: String)]
    let subject: String
    let body: String
    let attachments: [(name: String, size: Int, mimeType: String)]
    let status: String?

    init?(from props: [String: ChatJSONValue]) {
        guard let draftId = props["draftId"]?.stringValue,
              let subject = props["subject"]?.stringValue,
              let body = props["body"]?.stringValue else { return nil }
        self.draftId = draftId
        self.subject = subject
        self.body = body
        self.status = props["status"]?.stringValue

        func parseRecipients(_ key: String) -> [(name: String?, email: String)] {
            (props[key]?.arrayValue ?? []).compactMap { item in
                guard let obj = item.objectValue,
                      let email = obj["email"]?.stringValue else { return nil }
                return (name: obj["name"]?.stringValue, email: email)
            }
        }
        self.to = parseRecipients("to")
        self.cc = parseRecipients("cc")
        self.bcc = parseRecipients("bcc")

        self.attachments = (props["attachments"]?.arrayValue ?? []).compactMap { item in
            guard let obj = item.objectValue,
                  let name = obj["name"]?.stringValue,
                  let mimeType = obj["mimeType"]?.stringValue else { return nil }
            return (name: name, size: obj["size"]?.intValue ?? 0, mimeType: mimeType)
        }
    }
}

struct SuggestionsCardProps {
    struct Suggestion {
        let label: String
        let action: String
        let params: [String: String]
    }

    let suggestions: [Suggestion]

    init?(from props: [String: ChatJSONValue]) {
        guard let arr = props["suggestions"]?.arrayValue else { return nil }
        self.suggestions = arr.compactMap { item in
            guard let obj = item.objectValue,
                  let label = obj["label"]?.stringValue,
                  let action = obj["action"]?.stringValue else { return nil }
            var params: [String: String] = [:]
            if let paramsObj = obj["params"]?.objectValue {
                for (key, value) in paramsObj {
                    if let str = value.stringValue { params[key] = str }
                }
            }
            return Suggestion(label: label, action: action, params: params)
        }
    }
}

struct ActionConfirmationCardProps {
    let icon: String?
    let message: String
    let undoAction: String?
    let undoParams: [String: String]

    init?(from props: [String: ChatJSONValue]) {
        guard let message = props["message"]?.stringValue else { return nil }
        self.icon = props["icon"]?.stringValue
        self.message = message
        self.undoAction = props["undoAction"]?.stringValue
        var params: [String: String] = [:]
        if let paramsObj = props["undoParams"]?.objectValue {
            for (key, value) in paramsObj {
                if let str = value.stringValue { params[key] = str }
            }
        }
        self.undoParams = params
    }
}

struct QuoteCardProps {
    let quote: String
    let sourceLabel: String?
    let sourceAction: String?
    let sourceParams: [String: String]

    init?(from props: [String: ChatJSONValue]) {
        guard let quote = props["quote"]?.stringValue else { return nil }
        self.quote = quote
        self.sourceLabel = props["sourceLabel"]?.stringValue
        self.sourceAction = props["sourceAction"]?.stringValue
        var params: [String: String] = [:]
        if let paramsObj = props["sourceParams"]?.objectValue {
            for (key, value) in paramsObj {
                if let str = value.stringValue { params[key] = str }
            }
        }
        self.sourceParams = params
    }
}

// MARK: - Round 2 Card Props

struct AttachmentCardProps {
    let name: String
    let size: Int
    let mimeType: String
    let previewUrl: String?
    let downloadAction: String?
    let downloadParams: [String: String]

    init?(from props: [String: ChatJSONValue]) {
        guard let name = props["name"]?.stringValue,
              let mimeType = props["mimeType"]?.stringValue else { return nil }
        self.name = name
        self.size = props["size"]?.intValue ?? 0
        self.mimeType = mimeType
        self.previewUrl = props["previewUrl"]?.stringValue
        self.downloadAction = props["downloadAction"]?.stringValue
        var params: [String: String] = [:]
        if let obj = props["downloadParams"]?.objectValue {
            for (k, v) in obj { if let s = v.stringValue { params[k] = s } }
        }
        self.downloadParams = params
    }
}

struct CodeBlockCardProps {
    let language: String
    let code: String
    let filename: String?

    init?(from props: [String: ChatJSONValue]) {
        guard let code = props["code"]?.stringValue else { return nil }
        self.language = props["language"]?.stringValue ?? "text"
        self.code = code
        self.filename = props["filename"]?.stringValue
    }
}

struct ChecklistCardProps {
    struct Item: Identifiable {
        let id: String
        let label: String
        let done: Bool
    }
    let title: String?
    let items: [Item]

    init?(from props: [String: ChatJSONValue]) {
        guard let arr = props["items"]?.arrayValue else { return nil }
        self.title = props["title"]?.stringValue
        self.items = arr.compactMap { item in
            guard let obj = item.objectValue,
                  let id = obj["id"]?.stringValue,
                  let label = obj["label"]?.stringValue else { return nil }
            return Item(id: id, label: label, done: obj["done"]?.boolValue ?? false)
        }
    }
}

struct DocumentCardProps {
    let documentId: String
    let title: String
    let snippet: String?
    let updatedAt: String?
    let workspaceName: String?

    init?(from props: [String: ChatJSONValue]) {
        guard let id = props["documentId"]?.stringValue,
              let title = props["title"]?.stringValue else { return nil }
        self.documentId = id
        self.title = title
        self.snippet = props["snippet"]?.stringValue
        self.updatedAt = props["updatedAt"]?.stringValue
        self.workspaceName = props["workspaceName"]?.stringValue
    }
}

struct WeeklyAgendaCardProps {
    struct Day: Identifiable {
        var id: String { date }
        let date: String
        let eventCount: Int
        let taskCount: Int
        let label: String?
    }
    let weekStart: String
    let days: [Day]

    init?(from props: [String: ChatJSONValue]) {
        guard let weekStart = props["weekStart"]?.stringValue,
              let arr = props["days"]?.arrayValue else { return nil }
        self.weekStart = weekStart
        self.days = arr.compactMap { item in
            guard let obj = item.objectValue,
                  let date = obj["date"]?.stringValue else { return nil }
            return Day(
                date: date,
                eventCount: obj["eventCount"]?.intValue ?? 0,
                taskCount: obj["taskCount"]?.intValue ?? 0,
                label: obj["label"]?.stringValue
            )
        }
    }
}

struct MetricCardProps {
    let label: String
    let value: String
    let delta: String?
    let deltaDirection: String?
    let helpText: String?

    init?(from props: [String: ChatJSONValue]) {
        guard let label = props["label"]?.stringValue,
              let value = props["value"]?.stringValue else { return nil }
        self.label = label
        self.value = value
        self.delta = props["delta"]?.stringValue
        self.deltaDirection = props["deltaDirection"]?.stringValue
        self.helpText = props["helpText"]?.stringValue
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
              let jsonRange = Range(match.range(at: 1), in: content),
              let matchRange = Range(match.range, in: content) else {
            return ParseResult(textBefore: content, spec: nil, textAfter: "")
        }

        let jsonString = String(content[jsonRange])
        let spec: ChatUISpec? = {
            guard let data = jsonString.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(ChatUISpec.self, from: data)
        }()

        let textBefore = String(content[content.startIndex..<matchRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let textAfter = String(content[matchRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

        return ParseResult(textBefore: textBefore, spec: spec, textAfter: textAfter)
    }
}
