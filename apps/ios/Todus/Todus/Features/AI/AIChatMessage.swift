import Foundation

// MARK: - WebSource

/// A web search result source cited in an AI response.
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
    /// Web search sources cited in this response
    var sources: [WebSource]
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

    init(
        id: UUID = UUID(),
        role: Role,
        content: String = "",
        isStreaming: Bool = false,
        taskMutations: [AIChatTaskMutation] = [],
        uiSpec: ChatUISpec? = nil,
        source: MessageSource = .text,
        sources: [WebSource] = [],
        searchQueries: [String] = [],
        searchState: SearchPhase = .none,
        reasoningContent: String = "",
        reasoningDurationMs: Int? = nil,
        mentions: [RichInputMentionRef] = [],
        attachmentFileNames: [String] = []
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
