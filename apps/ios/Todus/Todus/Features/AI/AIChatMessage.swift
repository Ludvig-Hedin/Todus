import Foundation

// MARK: - WebSource

/// A web search result source cited in an AI response.
/// Retained for the legacy `sources` SSE event so markdown citation numbers
/// `[1]`, `[2]` keep resolving. New rendering uses `AISource`.
struct WebSource: Identifiable, Codable {
    let id: UUID
    let url: String
    let title: String
    let snippet: String

    /// Extracts the domain name from the URL for display (e.g. "example.com")
    var domain: String {
        URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? url
    }

    init(id: UUID = UUID(), url: String, title: String, snippet: String) {
        self.id = id
        self.url = url
        self.title = title
        self.snippet = snippet
    }
}

// MARK: - AISource

/// One piece of context the AI consumed for this turn — surfaced in the
/// "Sources" affordance under the assistant message. Mirrors the backend
/// `AISource` interface in `apps/server/src/lib/ai-sources.ts`.
struct AISource: Identifiable, Codable, Equatable, Hashable {
    enum Kind: String, Codable, Equatable, Hashable {
        case web, email, meeting
        case calendarEvent = "calendar_event"
        case document, note, thread, memory, task, company, unknown

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            self = Kind(rawValue: rawValue) ?? .unknown
        }
    }

    enum Platform: String, Codable, Equatable, Hashable {
        case gmail
        case googleMeet = "google_meet"
        case googleCalendar = "google_calendar"
        case appleCalendar = "apple_calendar"
        case website, notion, document, notes, todus, memory, upsales, unknown

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            self = Platform(rawValue: rawValue) ?? .unknown
        }
    }

    let id: String
    let kind: Kind
    let platform: Platform
    let title: String
    let subtitle: String?
    /// ISO-8601 string from the backend; converted to Date by `timestampDate`.
    /// Stored as a string so the default JSON decoder doesn't need a custom
    /// date strategy (the backend emits strings, not numeric reference dates).
    let timestamp: String?
    let url: String?
    let entityId: String?
    let snippet: String?
    let iconHint: String?

    init(
        id: String,
        kind: Kind,
        platform: Platform,
        title: String,
        subtitle: String? = nil,
        timestamp: Date? = nil,
        url: String? = nil,
        entityId: String? = nil,
        snippet: String? = nil,
        iconHint: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.platform = platform
        self.title = title
        self.subtitle = subtitle
        self.timestamp = timestamp.map { ISO8601DateFormatter().string(from: $0) }
        self.url = url
        self.entityId = entityId
        self.snippet = snippet
        self.iconHint = iconHint
    }

    /// Promote a legacy WebSource into an AISource for the unified sheet.
    init(web: WebSource) {
        let host = URL(string: web.url)?.host?.replacingOccurrences(of: "www.", with: "")
        self.id = "web:\(web.url)"
        self.kind = .web
        self.platform = .website
        self.title = web.title.isEmpty ? (host ?? web.url) : web.title
        self.subtitle = host
        self.timestamp = nil
        self.url = web.url
        self.entityId = nil
        self.snippet = web.snippet
        self.iconHint = host
    }

    /// Lazily parse the ISO-8601 string back into a Date for display.
    /// Tries both `withFractionalSeconds` and the plain Internet date-time
    /// shape so timestamps emitted by either Swift's default ISO8601
    /// formatter or the backend's `Date.toISOString()` parse cleanly.
    /// ISO8601DateFormatter is not thread-safe, so we instantiate per-call
    /// rather than sharing static instances across isolation domains.
    var timestampDate: Date? {
        guard let timestamp else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: timestamp) {
            return date
        }
        return ISO8601DateFormatter().date(from: timestamp)
    }
}

// MARK: - AIChatMessage

/// A single message in the AI chat conversation.
struct AIChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    /// Indicates whether the message originated from text chat or a live voice session.
    enum MessageSource {
        case text
        case voice
    }

    /// Tracks the web search phase for progressive UI rendering.
    enum SearchPhase {
        case none       // No web search for this message
        case searching  // Backend is actively searching
        case complete   // Sources received, answer streaming
    }

    let id: UUID
    var role: Role
    /// Text content — grows token-by-token during streaming
    var content: String
    /// True while the assistant response is still streaming in
    var isStreaming: Bool
    /// Task mutations the AI requested (create / update / delete)
    var taskMutations: [AIChatTaskMutation]
    /// Parsed generative UI spec embedded in the message (extracted from ```ui-spec blocks)
    var uiSpec: ChatUISpec?
    /// Whether this message came from text chat or a live voice session
    var source: MessageSource
    /// All context sources the AI consumed this turn — web search, mentions,
    /// memories, and tool-call results. Populated from the `context_sources`
    /// SSE event plus client-side tool capture.
    var sources: [AISource]
    /// Search queries the backend executed
    var searchQueries: [String]
    /// Current search phase — drives the searching/sources UI
    var searchState: SearchPhase
    /// Reasoning/thinking text streamed separately from main content (V2)
    var reasoningContent: String
    /// Duration of reasoning phase in ms (V2)
    var reasoningDurationMs: Int?
    /// Structured mention refs attached to this user message. Persisted so that
    /// follow-up turns can still resolve the underlying entity IDs (task, thread, event)
    /// that were mentioned in earlier turns.
    var mentions: [RichInputMentionRef]
    /// Local `AttachmentService` filenames included with this user message (for thread UI + resend on retry)
    var attachmentFileNames: [String]
    /// Inline error footer attached to a partially-streamed assistant bubble
    /// (network drop, rate limit). Distinct from a clobbered `content` value
    /// so retry can pick up where the stream left off without losing context.
    var errorMessage: String?
    /// Optional context chip label — shown as an attachment-style pill above the user bubble
    /// when the message was sent with an email thread or page context attached.
    var contextLabel: String?
    /// SF Symbol name for the context chip pill (e.g. "envelope.fill", "house.fill").
    var contextIcon: String?

    init(
        id: UUID = UUID(),
        role: Role,
        content: String = "",
        isStreaming: Bool = false,
        taskMutations: [AIChatTaskMutation] = [],
        uiSpec: ChatUISpec? = nil,
        source: MessageSource = .text,
        sources: [AISource] = [],
        searchQueries: [String] = [],
        searchState: SearchPhase = .none,
        reasoningContent: String = "",
        reasoningDurationMs: Int? = nil,
        mentions: [RichInputMentionRef] = [],
        attachmentFileNames: [String] = [],
        errorMessage: String? = nil,
        contextLabel: String? = nil,
        contextIcon: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
        self.taskMutations = taskMutations
        self.uiSpec = uiSpec
        self.source = source
        self.sources = sources
        self.searchQueries = searchQueries
        self.searchState = searchState
        self.reasoningContent = reasoningContent
        self.reasoningDurationMs = reasoningDurationMs
        self.mentions = mentions
        self.attachmentFileNames = attachmentFileNames
        self.errorMessage = errorMessage
        self.contextLabel = contextLabel
        self.contextIcon = contextIcon
    }

    /// Extracts and caches the UI spec from message content.
    /// Call this after streaming completes to parse any embedded specs.
    mutating func parseUISpec() {
        let result = ChatUISpecParser.parse(content)
        if let spec = result.spec {
            self.uiSpec = spec
            // Replace content with just the text portions (spec block removed)
            let cleanContent = [result.textBefore, result.textAfter]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            self.content = cleanContent
        }
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
    /// Whether the underlying tool call succeeded. `false` chips render as an
    /// inline error label so failures aren't silently dropped.
    var success: Bool
    /// Optional error label rendered when `success == false`.
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        action: Action,
        taskID: UUID? = nil,
        title: String? = nil,
        dueDate: Date? = nil,
        folderName: String? = nil,
        priority: String? = nil,
        status: String? = nil,
        success: Bool = true,
        errorMessage: String? = nil
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
        self.success = success
        self.errorMessage = errorMessage
    }
}
