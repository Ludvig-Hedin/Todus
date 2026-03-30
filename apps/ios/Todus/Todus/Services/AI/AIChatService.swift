import Foundation
import SwiftData
import Observation
import EventKit
import OSLog

// MARK: - AIChatService

/// Manages the AI chat conversation, streaming responses via the backend /api/ai/chat SSE endpoint.
/// Maintains message history, drives real-time token streaming, and applies task/calendar/email
/// mutations returned by the AI as tool calls.
@MainActor
@Observable
final class AIChatService {
    var messages: [AIChatMessage] = []
    var isStreaming: Bool = false
    var errorMessage: String?

    /// Title for the current conversation — set from first user message.
    var chatTitle: String? = nil

    /// Currently active model, selectable by the user at runtime.
    var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: "ai_selected_model") }
    }

    /// Whether the AI can read the user's task list (injected into the system prompt).
    var aiCanReadTasks: Bool = true {
        didSet { UserDefaults.standard.set(aiCanReadTasks, forKey: "ai_can_read_tasks") }
    }

    /// Whether the AI is allowed to create / edit / delete tasks via tool calls.
    var aiCanWriteTasks: Bool = true {
        didSet { UserDefaults.standard.set(aiCanWriteTasks, forKey: "ai_can_write_tasks") }
    }

    /// Whether the AI can read calendar events (injected into system prompt context).
    var aiCanReadCalendar: Bool = true {
        didSet { UserDefaults.standard.set(aiCanReadCalendar, forKey: "ai_can_read_calendar") }
    }

    /// Whether the AI can create calendar events via the create_calendar_event tool.
    var aiCanWriteCalendar: Bool = true {
        didSet { UserDefaults.standard.set(aiCanWriteCalendar, forKey: "ai_can_write_calendar") }
    }

    /// Whether the AI can read email threads (injected into system prompt context).
    var aiCanReadEmail: Bool = true {
        didSet { UserDefaults.standard.set(aiCanReadEmail, forKey: "ai_can_read_email") }
    }

    /// Whether the AI can send emails via the send_email tool.
    var aiCanSendEmail: Bool = true {
        didSet { UserDefaults.standard.set(aiCanSendEmail, forKey: "ai_can_send_email") }
    }

    /// Chronologically ordered list of saved conversations (newest first).
    var savedConversations: [AIChatConversation] = []
    /// Conversations deleted locally but not yet confirmed removed by the backend.
    private var locallyDeletedConversationIDs: Set<UUID> = []

    /// Tone instruction injected from AppServices.aiTonePreference — appended to the system prompt.
    var toneInstruction: String = ""

    private let configuration: AppConfiguration
    private let captureService: TaskCaptureService
    /// Auth service provides the Bearer token for backend API calls
    private weak var authService: AuthService?
    /// API client for tRPC calls (conversation sync)
    private weak var apiClient: TodosAPIClient?
    /// Calendar service for creating/reading EventKit events
    private var calendarService: CalendarService?
    /// Email service for reading threads and sending emails
    private weak var emailService: EmailService?
    private var streamingTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.todus.ios", category: "AIChatService")

    // MARK: - Token batching
    // Buffer rapid SSE tokens and flush every 40 ms so SwiftUI re-renders less often,
    // giving the typewriter animation a smoother, less-jittery feel.
    private var tokenBuffer = ""
    private var flushScheduled = false

    // Tracks whether the current conversation has been persisted so we can
    // auto-save on sheet-dismiss without creating duplicate entries.
    private var isConversationSaved = true

    // Cached calendar context string — fetched async before each stream so buildPayload stays sync.
    private var calendarSnapshot: String? = nil

    /// Current page/tab context injected by the view before each send — included in system prompt.
    var currentPageContext: String? = nil

    /// Structured mentions for the current outbound user turn.
    private var currentTurnMentions: [RichInputMentionRef] = []
    /// Preserved mention refs for the last submitted user turn so retry can resend them
    /// even after the active request state has been cleared.
    private var lastSubmittedMentions: [RichInputMentionRef] = []

    init(
        configuration: AppConfiguration,
        captureService: TaskCaptureService,
        authService: AuthService? = nil,
        apiClient: TodosAPIClient? = nil,
        calendarService: CalendarService? = nil,
        emailService: EmailService? = nil
    ) {
        self.configuration = configuration
        self.captureService = captureService
        self.authService = authService
        self.apiClient = apiClient
        self.calendarService = calendarService
        self.emailService = emailService

        // Restore persisted preferences
        self.selectedModel = UserDefaults.standard.string(forKey: "ai_selected_model")
            ?? configuration.primaryModel
        if UserDefaults.standard.object(forKey: "ai_can_read_tasks") != nil {
            self.aiCanReadTasks = UserDefaults.standard.bool(forKey: "ai_can_read_tasks")
        }
        if UserDefaults.standard.object(forKey: "ai_can_write_tasks") != nil {
            self.aiCanWriteTasks = UserDefaults.standard.bool(forKey: "ai_can_write_tasks")
        }
        if UserDefaults.standard.object(forKey: "ai_can_read_calendar") != nil {
            self.aiCanReadCalendar = UserDefaults.standard.bool(forKey: "ai_can_read_calendar")
        }
        if UserDefaults.standard.object(forKey: "ai_can_write_calendar") != nil {
            self.aiCanWriteCalendar = UserDefaults.standard.bool(forKey: "ai_can_write_calendar")
        }
        if UserDefaults.standard.object(forKey: "ai_can_read_email") != nil {
            self.aiCanReadEmail = UserDefaults.standard.bool(forKey: "ai_can_read_email")
        }
        if UserDefaults.standard.object(forKey: "ai_can_send_email") != nil {
            self.aiCanSendEmail = UserDefaults.standard.bool(forKey: "ai_can_send_email")
        }

        loadPersistedDeletedConversationIDs()

        // Defer conversation history loading — JSON deserialization from UserDefaults
        // can be slow with many saved conversations and blocks the main thread during startup.
        Task { @MainActor in
            loadPersistedConversations()
        }
    }

    // MARK: - Public API

    /// Send a user message and stream the AI response.
    func send(
        userMessage: String,
        mentions: [RichInputMentionRef] = [],
        allTasks: [TaskRecord],
        modelContext: ModelContext
    ) {
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        // Set title from first user message (truncated to 60 chars)
        if chatTitle == nil {
            chatTitle = String(trimmed.prefix(60))
        }

        // New messages make the conversation unsaved
        isConversationSaved = false
        currentTurnMentions = mentions
        lastSubmittedMentions = mentions

        // Append user message with its mention refs so they persist across turns.
        // Follow-up turns can then resolve entity IDs from earlier mentions.
        messages.append(AIChatMessage(role: .user, content: trimmed, mentions: mentions))

        // Append an empty placeholder the streaming response will fill
        let assistantID = UUID()
        messages.append(AIChatMessage(id: assistantID, role: .assistant, isStreaming: true))
        isStreaming = true
        errorMessage = nil

        streamingTask = Task { [weak self] in
            guard let self else { return }
            await self.streamResponse(
                assistantMessageID: assistantID,
                allTasks: allTasks,
                modelContext: modelContext
            )
        }
    }

    /// Retry the last user message (used when the backend was unreachable).
    /// Removes any failed assistant placeholder and re-sends the last user message.
    func retry(allTasks: [TaskRecord], modelContext: ModelContext) {
        guard !isStreaming else { return }
        guard let assistantID = messages.last(where: { $0.role == .assistant })?.id else {
            errorMessage = nil
            return
        }
        retry(
            assistantMessageID: assistantID,
            allTasks: allTasks,
            modelContext: modelContext
        )
    }

    /// Whether a specific assistant message can be retried.
    func canRetry(assistantMessageID: UUID) -> Bool {
        guard !isStreaming,
              let assistantIndex = messages.firstIndex(where: { $0.id == assistantMessageID }),
              messages[assistantIndex].role == .assistant else {
            return false
        }

        return messages[..<assistantIndex].last(where: { $0.role == .user }) != nil
    }

    /// Retry a specific assistant turn in place so the message row is replaced, not duplicated.
    func retry(
        assistantMessageID: UUID,
        allTasks: [TaskRecord],
        modelContext: ModelContext
    ) {
        guard canRetry(assistantMessageID: assistantMessageID),
              let assistantIndex = messages.firstIndex(where: { $0.id == assistantMessageID }),
              let userMessage = messages[..<assistantIndex].last(where: { $0.role == .user }) else {
            errorMessage = nil
            return
        }

        errorMessage = nil
        isConversationSaved = false
        currentTurnMentions = userMessage.mentions
        lastSubmittedMentions = userMessage.mentions

        if assistantIndex + 1 < messages.count {
            // Remove dependent turns after the retried assistant message so the
            // next request cannot mix stale follow-up context with the retried branch.
            messages.removeSubrange((assistantIndex + 1)..<messages.count)
        }

        messages[assistantIndex].content = ""
        messages[assistantIndex].isStreaming = true
        messages[assistantIndex].taskMutations = []
        messages[assistantIndex].uiSpec = nil
        messages[assistantIndex].sources = []
        messages[assistantIndex].searchQueries = []
        messages[assistantIndex].searchState = .none
        messages[assistantIndex].reasoningContent = ""
        messages[assistantIndex].reasoningDurationMs = nil

        isStreaming = true
        let requestMessages = Array(messages.prefix(assistantIndex))

        streamingTask = Task { [weak self] in
            guard let self else { return }
            await self.streamResponse(
                assistantMessageID: assistantMessageID,
                requestMessages: requestMessages,
                allTasks: allTasks,
                modelContext: modelContext
            )
        }
    }

    /// Cancel an in-progress stream.
    func cancelStream() {
        streamingTask?.cancel()
        streamingTask = nil
        if let streamingMessageID = messages.first(where: \.isStreaming)?.id {
            finaliseStream(messageID: streamingMessageID)
        } else {
            isStreaming = false
            currentTurnMentions = []
            flushScheduled = false
            tokenBuffer = ""
        }
    }

    /// Save the current conversation to history and reset to a clean slate.
    func clearHistory() {
        if !messages.isEmpty && !isConversationSaved {
            saveCurrentConversation()
        }
        messages.removeAll()
        chatTitle = nil
        errorMessage = nil
        isConversationSaved = true
        currentTurnMentions = []
        lastSubmittedMentions = []
    }

    /// Auto-save when the user closes the chat sheet without explicitly starting a new chat.
    /// Safe to call multiple times — skips if already saved or empty.
    func autosave() {
        guard !messages.isEmpty, !isConversationSaved else { return }
        saveCurrentConversation()
        isConversationSaved = true
    }

    /// Restore a saved conversation into the active session.
    func loadConversation(_ conversation: AIChatConversation) {
        if isStreaming {
            cancelStream()
        }

        messages = conversation.messages.map { saved in
            AIChatMessage(
                role: saved.role == "user" ? .user : .assistant,
                content: saved.content,
                isStreaming: false,
                mentions: saved.mentions
            )
        }
        chatTitle = conversation.title
        errorMessage = nil
        currentTurnMentions = []
        lastSubmittedMentions = []
        // Already persisted — don't duplicate on next autosave
        isConversationSaved = true
    }

    /// Creates a duplicated working copy of the current conversation while preserving
    /// all message metadata needed for follow-up actions and retries.
    func duplicateCurrentConversation() {
        guard !messages.isEmpty else { return }

        if isStreaming {
            cancelStream()
        }

        autosave()

        let duplicatedMessages = messages
        let duplicatedTitle = (chatTitle ?? "Untitled") + " (copy)"

        messages = duplicatedMessages
        chatTitle = duplicatedTitle
        errorMessage = nil
        currentTurnMentions = []
        lastSubmittedMentions = []
        isConversationSaved = false
    }

    /// Delete a saved conversation from history (local + backend).
    func deleteConversation(_ conversation: AIChatConversation) {
        locallyDeletedConversationIDs.insert(conversation.id)
        persistDeletedConversationIDs()
        savedConversations.removeAll { $0.id == conversation.id }
        persistConversationsLocally()
        // Delete from backend in background — fire-and-forget
        Task { await syncDeleteConversation(id: conversation.id.uuidString) }
    }

    // MARK: - Voice Chat Integration

    /// Append finalized voice exchanges to the main chat history.
    /// Called by VoiceChatViewModel when the voice session ends or a turn completes.
    func appendVoiceExchange(userText: String, assistantText: String) {
        if !userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(AIChatMessage(role: .user, content: userText, source: .voice))
        }
        if !assistantText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(AIChatMessage(role: .assistant, content: assistantText, source: .voice))
        }
        isConversationSaved = false
    }

    /// Build the system prompt for a voice session, reusing the same context pipeline as text chat.
    /// Returns just the system prompt string (not the full request payload).
    func buildSystemPromptForVoice(allTasks: [TaskRecord]) async -> String {
        await refreshCalendarSnapshot()
        let payload = buildPayload(allTasks: allTasks)
        // The first message in the payload is always the system prompt
        return payload.messages.first?.content ?? ""
    }

    /// Process a tool call from a voice session. Returns a result string to send back to the model.
    func processVoiceToolCall(
        name: String,
        arguments: String,
        modelContext: ModelContext
    ) async -> String {
        guard let argsData = arguments.data(using: .utf8) else {
            return "{\"error\": \"Invalid arguments\"}"
        }

        switch name {
        case "create_task":
            // Respect aiCanWriteTasks permission (same as text chat path)
            guard aiCanWriteTasks else {
                return encodeToolResult(success: false, message: "AI is not allowed to write tasks")
            }
            if let args = try? JSONDecoder().decode(CreateTaskArgs.self, from: argsData) {
                let dueDate = args.dueDate.flatMap { ISO8601DateFormatter().date(from: $0) }
                captureService.capture(
                    rawComposerText: args.title,
                    overrideDueDate: dueDate,
                    in: modelContext
                )
                return encodeToolResult(success: true, message: "Task '\(args.title)' created")
            }

        case "update_task":
            guard aiCanWriteTasks else {
                return encodeToolResult(success: false, message: "AI is not allowed to write tasks")
            }
            if let args = try? JSONDecoder().decode(UpdateTaskArgs.self, from: argsData),
               let taskID = UUID(uuidString: args.id) {
                applyUpdateTask(taskID: taskID, args: args, modelContext: modelContext)
                return encodeToolResult(success: true, message: "Task updated")
            }

        case "delete_task":
            guard aiCanWriteTasks else {
                return encodeToolResult(success: false, message: "AI is not allowed to write tasks")
            }
            if let args = try? JSONDecoder().decode(DeleteTaskArgs.self, from: argsData),
               let taskID = UUID(uuidString: args.id) {
                applyDeleteTask(taskID: taskID, modelContext: modelContext)
                return encodeToolResult(success: true, message: "Task deleted")
            }

        case "create_calendar_event":
            if aiCanWriteCalendar,
               let args = try? JSONDecoder().decode(CreateCalendarEventArgs.self, from: argsData) {
                let iso = ISO8601DateFormatter()
                if let startDate = iso.date(from: args.startDate),
                   let cal = calendarService, cal.canCreateEvents() {
                    let endDate = args.endDate.flatMap { iso.date(from: $0) }
                    do {
                        try await cal.createEvent(title: args.title, startDate: startDate, endDate: endDate)
                        return encodeToolResult(success: true, message: "Calendar event '\(args.title)' created")
                    } catch {
                        return encodeToolResult(success: false, message: "Failed to create event: \(error.localizedDescription)")
                    }
                }
            }

        case "send_email":
            if aiCanSendEmail,
               let args = try? JSONDecoder().decode(SendEmailArgs.self, from: argsData),
               let email = emailService {
                let draft = EmailDraft(
                    to: args.to,
                    subject: args.subject,
                    body: args.body,
                    replyToThreadId: args.threadId
                )
                let sent = await email.sendEmail(draft)
                if sent {
                    return encodeToolResult(success: true, message: "Email sent: \(args.subject)")
                } else {
                    return encodeToolResult(success: false, message: "Failed to send email")
                }
            }

        default:
            break
        }

        return encodeToolResult(success: false, message: "Tool '\(name)' not found or invalid arguments")
    }

    /// Safely encodes a tool result as JSON using JSONEncoder, avoiding string interpolation
    /// bugs when the message contains quotes, backslashes, or other special characters.
    private func encodeToolResult(success: Bool, message: String) -> String {
        struct ToolResult: Encodable {
            let success: Bool
            let message: String
        }
        let result = ToolResult(success: success, message: message)
        if let data = try? JSONEncoder().encode(result),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        
        // Fallback: minimal safe JSON with basic sanitization
        let safeMessage = message.replacingOccurrences(of: "\"", with: "'")
                                 .replacingOccurrences(of: "\n", with: " ")
                                 .replacingOccurrences(of: "\\", with: "\\\\")
        return "{\"success\":\(success),\"message\":\"Result encoding failed, original message: \(safeMessage)\"}"
    }

    /// Returns the Gemini-format tool declarations for use in voice sessions.
    /// Maps from the OpenRouter function format used in text chat.
    func voiceToolDeclarations() -> [[String: Any]] {
        [
            [
                "name": "create_task",
                "description": "Create a new task for the user",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Task title"],
                        "dueDate": ["type": "string", "description": "ISO 8601 due date (optional)"],
                        "folderName": ["type": "string", "description": "Folder name (optional)"],
                        "priority": ["type": "string", "enum": ["none", "low", "medium", "high", "urgent"], "description": "Task priority"]
                    ],
                    "required": ["title"]
                ] as [String: Any]
            ],
            [
                "name": "update_task",
                "description": "Update an existing task",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "Task UUID"],
                        "title": ["type": "string"],
                        "status": ["type": "string", "enum": ["todo", "doing", "done"]],
                        "priority": ["type": "string", "enum": ["none", "low", "medium", "high", "urgent"]],
                        "dueDate": ["type": "string"]
                    ],
                    "required": ["id"]
                ] as [String: Any]
            ],
            [
                "name": "delete_task",
                "description": "Delete a task",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "Task UUID to delete"]
                    ],
                    "required": ["id"]
                ] as [String: Any]
            ],
            [
                "name": "create_calendar_event",
                "description": "Create a new calendar event",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Event title"],
                        "startDate": ["type": "string", "description": "ISO 8601 start datetime"],
                        "endDate": ["type": "string", "description": "ISO 8601 end datetime (optional)"],
                        "notes": ["type": "string", "description": "Event notes (optional)"]
                    ],
                    "required": ["title", "startDate"]
                ] as [String: Any]
            ],
            [
                "name": "send_email",
                "description": "Send an email on behalf of the user",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "to": ["type": "array", "items": ["type": "string"], "description": "Recipient email addresses"],
                        "subject": ["type": "string", "description": "Email subject"],
                        "body": ["type": "string", "description": "Email body"],
                        "threadId": ["type": "string", "description": "Thread ID to reply to (optional)"]
                    ],
                    "required": ["to", "subject", "body"]
                ] as [String: Any]
            ]
        ]
    }

    // MARK: - Streaming

    private func streamResponse(
        assistantMessageID: UUID,
        requestMessages: [AIChatMessage]? = nil,
        allTasks: [TaskRecord],
        modelContext: ModelContext
    ) async {
        defer { finaliseStream(messageID: assistantMessageID) }

        // Pre-fetch calendar events async so buildPayload stays sync
        await refreshCalendarSnapshot()

        // Route through the main backend's /api/ai/chat endpoint with Bearer auth
        let baseURL = configuration.effectiveBackendURL
        let url = baseURL.appending(path: "api/ai/chat")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authService?.bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let payload = buildPayload(allTasks: allTasks, conversationMessages: requestMessages)
        guard let body = try? JSONEncoder().encode(payload) else {
            appendError("Failed to encode request.", to: assistantMessageID)
            return
        }
        request.httpBody = body

        // Pre-flight: no token means certain 401 — fail fast with a clear message
        if authService?.bearerToken == nil {
            appendError("Not signed in. Please log in and try again.", to: assistantMessageID)
            return
        }

        do {
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                appendError("Invalid response from server.", to: assistantMessageID)
                return
            }
            debugHTTPResponse(http, context: "chat stream")
            // Capture rotated Bearer token from Better Auth's set-auth-token header
            authService?.captureRotatedToken(from: http)
            guard (200..<300).contains(http.statusCode) else {
                switch http.statusCode {
                case 401:
                    // Token exists in Keychain (user appears logged in) but backend session
                    // may have expired. Try silent refresh — if it succeeds the next retry
                    // (user taps retry button) will use the refreshed token automatically.
                    if let auth = authService {
                        let refreshed = await auth.attemptSilentRefresh()
                        if refreshed {
                            appendError("Session token refreshed. Please tap retry.", to: assistantMessageID)
                        } else {
                            auth.isSessionExpired = true
                            appendError(diagnosticAuthMessage(
                                statusCode: http.statusCode,
                                fallback: "Session expired. Please log out and back in."
                            ), to: assistantMessageID)
                        }
                    } else {
                        appendError(diagnosticAuthMessage(
                            statusCode: http.statusCode,
                            fallback: "Session expired. Please log out and back in."
                        ), to: assistantMessageID)
                    }
                case 503:
                    appendError("AI service is not configured on the server (missing OPENROUTER_API_KEY).", to: assistantMessageID)
                case 502:
                    appendError("AI provider error. The upstream AI service may be down.", to: assistantMessageID)
                default:
                    appendError(diagnosticHTTPMessage(statusCode: http.statusCode), to: assistantMessageID)
                }
                return
            }

            // Parse Server-Sent Events line by line
            for try await line in asyncBytes.lines {
                if Task.isCancelled { break }

                guard line.hasPrefix("data: ") else { continue }
                let jsonString = String(line.dropFirst(6))
                if jsonString == "[DONE]" { break }

                guard let data = jsonString.data(using: .utf8) else { continue }

                // Try custom event first (web search status, sources, reasoning)
                // These have a "type" field that SSEChunk doesn't, so one will succeed and the other fail.
                if let customEvent = try? JSONDecoder().decode(SSECustomEvent.self, from: data),
                   !customEvent.type.isEmpty {
                    handleCustomEvent(customEvent, messageID: assistantMessageID)
                    continue
                }

                // Fall through to existing OpenRouter SSE chunk parsing
                guard let chunk = try? JSONDecoder().decode(SSEChunk.self, from: data) else { continue }

                // Append delta content token-by-token → drives typewriter animation
                if let delta = chunk.choices.first?.delta.content, !delta.isEmpty {
                    appendToken(delta, to: assistantMessageID)
                }

                // Respect aiCanWriteTasks setting before applying tool calls
                if aiCanWriteTasks, let toolCalls = chunk.choices.first?.delta.toolCalls {
                    await processToolCalls(toolCalls, assistantMessageID: assistantMessageID, modelContext: modelContext)
                }
            }
        } catch {
            if !Task.isCancelled {
                log.error("chat stream failed: \(error.localizedDescription, privacy: .public)")
                appendError(error.localizedDescription, to: assistantMessageID)
            }
        }
    }

    private func debugHTTPResponse(_ http: HTTPURLResponse, context: String) {
        let authHeader = http.value(forHTTPHeaderField: "set-auth-token")?.isEmpty == false ? "present" : "missing"
        log.debug(
            "\(context, privacy: .public): HTTP \(http.statusCode) set-auth-token=\(authHeader, privacy: .public)"
        )
    }

    private func diagnosticHTTPMessage(statusCode: Int) -> String {
        return "Server error (\(statusCode))."
    }

    private func diagnosticAuthMessage(statusCode: Int, fallback: String) -> String {
        return fallback + " (HTTP \(statusCode))."
    }

    // MARK: - Custom Event Handling (Web Search + Reasoning)

    /// Process custom SSE events for web search status, sources, and reasoning tokens.
    /// Updates the assistant message's search/reasoning state to drive progressive UI rendering.
    private func handleCustomEvent(_ event: SSECustomEvent, messageID: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == messageID }) else { return }

        switch event.type {
        case "search_status":
            switch event.status {
            case "searching":
                messages[idx].searchState = .searching
                messages[idx].searchQueries = event.queries ?? []
            case "complete":
                messages[idx].searchState = .complete
                messages[idx].searchQueries = event.queries ?? []
            default:
                messages[idx].searchState = .none
                messages[idx].searchQueries = event.queries ?? []
            }

        case "sources":
            messages[idx].searchState = .complete
            messages[idx].sources = (event.sources ?? []).map { src in
                WebSource(url: src.url, title: src.title, snippet: src.snippet)
            }

        case "reasoning":
            if let content = event.content {
                messages[idx].reasoningContent += content
            }

        case "reasoning_done":
            messages[idx].reasoningDurationMs = event.durationMs

        default:
            break
        }
    }

    // MARK: - Payload Building

    /// Build the full request payload including system prompt, conversation history, and task context.
    /// Internal visibility so voice chat can access the system prompt via `buildSystemPromptForVoice`.
    func buildPayload(
        allTasks: [TaskRecord],
        conversationMessages: [AIChatMessage]? = nil
    ) -> ChatRequest {
        let activeMessages = conversationMessages ?? messages

        // ── Tasks ──────────────────────────────────────────────────────────────
        let taskSummaries: [TaskSummaryPayload] = aiCanReadTasks
            ? allTasks.prefix(100).map { task in
                TaskSummaryPayload(
                    id: task.id.uuidString,
                    title: task.title,
                    status: task.status.rawValue,
                    priority: task.priority.rawValue,
                    dueDate: task.dueDate.map { ISO8601DateFormatter().string(from: $0) },
                    folderName: task.folder?.name
                )
            }
            : []

        let taskContext = aiCanReadTasks
            ? "## Tasks (\(taskSummaries.count) total)\n\(Self.tasksToJSON(taskSummaries))"
            : "Task access is disabled by the user."

        let taskWriteNote = aiCanWriteTasks
            ? "You CAN create, update, and delete tasks via tool calls."
            : "You cannot modify tasks (read-only)."

        // ── Calendar — gated by aiCanReadCalendar ─────────────────────────────
        let calendarContext: String
        if !aiCanReadCalendar {
            calendarContext = "## Calendar\nCalendar access is disabled by the user."
        } else if let snap = calendarSnapshot {
            calendarContext = snap
        } else {
            calendarContext = "## Calendar\nCalendar access not granted or not yet loaded."
        }

        let calendarWriteNote = aiCanWriteCalendar
            ? "You CAN create calendar events via the create_calendar_event tool."
            : "You cannot create calendar events (write access disabled by user)."

        // ── Email — gated by aiCanReadEmail ──────────────────────────────────
        let emailContext: String
        if !aiCanReadEmail {
            emailContext = "## Email\nEmail access is disabled by the user."
        } else if let email = emailService, !email.threads.isEmpty {
            let recent = email.threads.prefix(10).map { t in
                "- [\(t.id)] \(t.unread ? "UNREAD" : "read") from \(t.from.name.isEmpty ? t.from.email : t.from.name): \"\(t.subject)\""
            }.joined(separator: "\n")
            let sendNote = aiCanSendEmail ? "You CAN send emails via the send_email tool." : "You cannot send emails (send access disabled by user)."
            emailContext = """
            ## Recent Emails (inbox)
            \(recent)
            \(sendNote)
            """
        } else {
            emailContext = "## Email\nNo email threads loaded or email not connected."
        }

        // ── System prompt ──────────────────────────────────────────────────────
        let toneLine = toneInstruction.isEmpty ? "" : "\n\(toneInstruction)"
        let pageContextLine = currentPageContext.map { "\nThe user is currently viewing: \($0)." } ?? ""
        let systemPrompt = """
        You are a powerful personal assistant embedded in Todus — a task manager, email client, and calendar app.
        Today is \(Self.formattedDate(Date())).\(toneLine)\(pageContextLine)

        You have full access to the user's tasks, calendar, and email:

        \(taskContext)
        \(taskWriteNote)

        \(calendarContext)
        \(calendarWriteNote)

        \(emailContext)

        CAPABILITIES — you can:
        • Read, create, update, and delete tasks (use create_task, update_task, delete_task tools)
        • Read calendar events and create new ones (use create_calendar_event tool)
        • Read email threads and send new emails or replies (use send_email tool)

        FORMATTING RULES — follow these exactly:
        • NEVER use markdown tables. Always use bullet lists (- item) for tabular data.
        • When referencing a task, write [task:UUID] on its own line — the app renders it as a native card.
        • Use ## for section headings, **bold** for emphasis, - for bullets.
        • Leave a blank line between sections and after bullet lists.
        • Be concise, action-oriented, and natural. Don't over-explain.
        """

        var apiMessages: [ChatMessage] = [ChatMessage(role: "system", content: systemPrompt)]
        apiMessages += activeMessages.compactMap { msg -> ChatMessage? in
            guard !msg.isStreaming || !msg.content.isEmpty else { return nil }
            let role = msg.role == .user ? "user" : "assistant"
            return ChatMessage(role: role, content: msg.content)
        }
        if apiMessages.last?.role == "assistant" && apiMessages.last?.content.isEmpty == true {
            apiMessages.removeLast()
        }

        // Collect mentions from ALL user messages in the conversation so that entity IDs
        // (task, thread, event) referenced in earlier turns remain resolvable in follow-up turns.
        // De-duplicate by mention ID to avoid sending the same ref multiple times.
        var seenMentionIDs = Set<String>()
        var allMentionPayloads: [MentionPayload] = []
        for msg in activeMessages where msg.role == .user {
            for ref in msg.mentions where !seenMentionIDs.contains(ref.id) {
                seenMentionIDs.insert(ref.id)
                allMentionPayloads.append(MentionPayload(
                    id: ref.id,
                    kind: ref.kind.rawValue,
                    title: ref.title,
                    subtitle: ref.subtitle,
                    displayText: ref.displayText,
                    accessibilityLabel: ref.accessibilityLabel
                ))
            }
        }

        return ChatRequest(
            messages: apiMessages,
            mentions: allMentionPayloads,
            tasks: Array(taskSummaries),
            model: selectedModel
        )
    }

    // MARK: - Tool Call Processing

    private func processToolCalls(
        _ toolCalls: [SSEToolCall],
        assistantMessageID: UUID,
        modelContext: ModelContext
    ) async {
        for toolCall in toolCalls {
            guard let argsData = toolCall.function.arguments.data(using: .utf8) else { continue }

            switch toolCall.function.name {
            case "create_task":
                if let args = try? JSONDecoder().decode(CreateTaskArgs.self, from: argsData) {
                    let dueDate = args.dueDate.flatMap { ISO8601DateFormatter().date(from: $0) }
                    captureService.capture(
                        rawComposerText: args.title,
                        overrideDueDate: dueDate,
                        in: modelContext
                    )
                    let mutation = AIChatTaskMutation(action: .create, title: args.title, dueDate: dueDate)
                    appendMutation(mutation, to: assistantMessageID)
                }

            case "update_task":
                if let args = try? JSONDecoder().decode(UpdateTaskArgs.self, from: argsData),
                   let taskID = UUID(uuidString: args.id) {
                    applyUpdateTask(taskID: taskID, args: args, modelContext: modelContext)
                    let mutation = AIChatTaskMutation(action: .update, taskID: taskID, title: args.title)
                    appendMutation(mutation, to: assistantMessageID)
                }

            case "delete_task":
                if let args = try? JSONDecoder().decode(DeleteTaskArgs.self, from: argsData),
                   let taskID = UUID(uuidString: args.id) {
                    applyDeleteTask(taskID: taskID, modelContext: modelContext)
                    let mutation = AIChatTaskMutation(action: .delete, taskID: taskID)
                    appendMutation(mutation, to: assistantMessageID)
                }

            case "create_calendar_event":
                if aiCanWriteCalendar,
                   let args = try? JSONDecoder().decode(CreateCalendarEventArgs.self, from: argsData) {
                    let iso = ISO8601DateFormatter()
                    if let startDate = iso.date(from: args.startDate),
                       let cal = calendarService, cal.canCreateEvents() {
                        let endDate = args.endDate.flatMap { iso.date(from: $0) }
                        // CalendarService is actor-isolated — call with await
                        try? await cal.createEvent(title: args.title, startDate: startDate, endDate: endDate)
                        let mutation = AIChatTaskMutation(action: .create, title: "📅 \(args.title)")
                        appendMutation(mutation, to: assistantMessageID)
                    }
                }

            case "send_email":
                if aiCanSendEmail,
                   let args = try? JSONDecoder().decode(SendEmailArgs.self, from: argsData),
                   let email = emailService {
                    let draft = EmailDraft(
                        to: args.to,
                        subject: args.subject,
                        body: args.body,
                        replyToThreadId: args.threadId
                    )
                    Task { await email.sendEmail(draft) }
                    let mutation = AIChatTaskMutation(action: .create, title: "✉️ Sent: \(args.subject)")
                    appendMutation(mutation, to: assistantMessageID)
                }

            default:
                break
            }
        }
    }

    private func applyUpdateTask(taskID: UUID, args: UpdateTaskArgs, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == taskID })
        guard let task = (try? modelContext.fetch(descriptor))?.first else { return }

        if let title = args.title { task.title = title }
        if let dueDateStr = args.dueDate { task.dueDate = ISO8601DateFormatter().date(from: dueDateStr) }
        if let statusStr = args.status { task.status = TaskStatus(rawValue: statusStr) ?? task.status }
        if let priorityStr = args.priority { task.priority = AppTaskPriority(rawValue: priorityStr) ?? task.priority }
        task.updatedAt = .now
        task.syncState = .pendingUpload
        try? modelContext.save()
    }

    private func applyDeleteTask(taskID: UUID, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == taskID })
        guard let task = (try? modelContext.fetch(descriptor))?.first else { return }
        captureService.delete(task, in: modelContext)
    }

    // MARK: - Message Mutation Helpers

    /// Buffer tokens and flush every 40 ms so the UI re-renders in batches rather
    /// than on every single SSE event — this removes the jitter from rapid streaming.
    private func appendToken(_ token: String, to messageID: UUID) {
        tokenBuffer += token
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self else { return }
            self.flushTokenBuffer(to: messageID)
            self.flushScheduled = false
        }
    }

    private func flushTokenBuffer(to messageID: UUID) {
        guard !tokenBuffer.isEmpty,
              let idx = messages.firstIndex(where: { $0.id == messageID }) else {
            tokenBuffer = ""
            return
        }
        messages[idx].content += tokenBuffer
        tokenBuffer = ""
    }

    private func appendError(_ text: String, to messageID: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[idx].content = "⚠️ \(text)"
        messages[idx].isStreaming = false
    }

    private func appendMutation(_ mutation: AIChatTaskMutation, to messageID: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[idx].taskMutations.append(mutation)
    }

    private func finaliseStream(messageID: UUID) {
        isStreaming = false
        currentTurnMentions = []
        flushScheduled = false
        if let idx = messages.firstIndex(where: { $0.id == messageID }) {
            // Flush any buffered tokens before marking stream as complete so the
            // last few tokens aren't lost when the stream ends mid-batch.
            if !tokenBuffer.isEmpty {
                messages[idx].content += tokenBuffer
                tokenBuffer = ""
            }
            messages[idx].isStreaming = false
            // Parse any embedded generative UI spec from the completed message.
            // This extracts ```ui-spec JSON blocks and stores the decoded spec
            // on the message, removing the raw JSON from the displayed content.
            messages[idx].parseUISpec()
        }
    }

    // MARK: - History Persistence

    private func saveCurrentConversation() {
        guard !messages.isEmpty else { return }
        let saved = AIChatConversation(
            id: UUID(),
            title: chatTitle ?? "Untitled",
            createdAt: Date(),
            messages: messages.map {
                AIChatConversation.SavedMessage(
                    role: $0.role == .user ? "user" : "assistant",
                    content: $0.content,
                    mentions: $0.mentions
                )
            }
        )
        savedConversations.insert(saved, at: 0)
        // Cap history at 50 conversations
        if savedConversations.count > 50 { savedConversations.removeLast() }
        persistConversationsLocally()
        // Sync new conversation to backend in background
        Task { await syncSaveConversation(saved) }
    }

    private static let chatHistoryKey = "com.todus.ai.chatHistory"
    private static let deletedConversationIDsKey = "com.todus.ai.deletedConversationIDs"

    /// Persist to Keychain as a local cache (fast, survives reinstall)
    private func persistConversationsLocally() {
        guard let data = try? JSONEncoder().encode(savedConversations) else { return }
        KeychainHelper.saveData(key: Self.chatHistoryKey, value: data)
    }

    private func persistDeletedConversationIDs() {
        guard let data = try? JSONEncoder().encode(Array(locallyDeletedConversationIDs)) else { return }
        KeychainHelper.saveData(key: Self.deletedConversationIDsKey, value: data)
    }

    private func loadPersistedDeletedConversationIDs() {
        if let data = KeychainHelper.readData(key: Self.deletedConversationIDsKey),
           let ids = try? JSONDecoder().decode([UUID].self, from: data) {
            locallyDeletedConversationIDs = Set(ids)
        }
    }

    private func loadPersistedConversations() {
        // Load local cache immediately for fast UI
        if let data = KeychainHelper.readData(key: Self.chatHistoryKey),
           let convs = try? JSONDecoder().decode([AIChatConversation].self, from: data) {
            savedConversations = convs
        }
        // Migrate from UserDefaults (old location) if present
        else if let data = UserDefaults.standard.data(forKey: "ai_chat_history"),
                let convs = try? JSONDecoder().decode([AIChatConversation].self, from: data) {
            savedConversations = convs
            persistConversationsLocally()
            UserDefaults.standard.removeObject(forKey: "ai_chat_history")
        }
        // Then fetch from backend to get conversations from other devices
        Task { await syncLoadConversations() }
    }

    // MARK: - Backend Sync

    /// Codable wrapper matching the backend tRPC response for conversation list
    private struct ConversationListResponse: Decodable {
        let conversations: [RemoteConversation]
    }

    private struct RemoteConversation: Decodable {
        let id: String
        let title: String
        let createdAt: Date
        let updatedAt: Date
        // Only included in getConversation, not listConversations
        let messages: [AIChatConversation.SavedMessage]?
    }

    private struct SyncSuccess: Decodable {
        let success: Bool
    }

    /// Fetch conversation list from backend and merge with local cache
    private func syncLoadConversations() async {
        guard let api = apiClient else { return }
        let preSyncIDs = Set(savedConversations.map { $0.id })
        let preSyncDeletedIDs = locallyDeletedConversationIDs
        do {
            let response: ConversationListResponse = try await api.trpcQuery("ai.listConversations")
            let remoteConvos = response.conversations
            let deletedIDsToSkip = preSyncDeletedIDs.union(locallyDeletedConversationIDs)
            var mergedByID = Dictionary(uniqueKeysWithValues: savedConversations.map { ($0.id, $0) })
            for remote in remoteConvos {
                guard let uuid = UUID(uuidString: remote.id),
                      !deletedIDsToSkip.contains(uuid) else {
                    continue
                }

                // Fetch full conversation with messages and update the local item in place.
                if let full = await fetchFullConversation(id: remote.id) {
                    guard !deletedIDsToSkip.contains(full.id) else { continue }
                    mergedByID[full.id] = full
                }
            }
            var merged = Array(mergedByID.values)
            // Sort by creation date (newest first) and cap at 50
            merged.sort { $0.createdAt > $1.createdAt }
            if merged.count > 50 { merged = Array(merged.prefix(50)) }
            savedConversations = merged
            persistConversationsLocally()

            // Upload any local-only conversations that aren't on the server
            let remoteIDs = Set(remoteConvos.compactMap { UUID(uuidString: $0.id) })
            for convo in merged
                where preSyncIDs.contains(convo.id)
                && !remoteIDs.contains(convo.id)
                && !deletedIDsToSkip.contains(convo.id) {
                await syncSaveConversation(convo)
            }
            await syncPendingDeletedConversations()
        } catch {
            // Backend unreachable — local cache is still available, no action needed
            await syncPendingDeletedConversations()
        }
    }

    /// Fetch a single conversation with full messages from the backend
    private func fetchFullConversation(id: String) async -> AIChatConversation? {
        guard let api = apiClient else { return nil }
        struct GetInput: Encodable { let id: String }
        do {
            let remote: RemoteConversation = try await api.trpcQuery("ai.getConversation", input: GetInput(id: id))
            guard let uuid = UUID(uuidString: remote.id) else { return nil }
            return AIChatConversation(
                id: uuid,
                title: remote.title,
                createdAt: remote.createdAt,
                messages: remote.messages ?? []
            )
        } catch {
            return nil
        }
    }

    /// Save a conversation to the backend
    private func syncSaveConversation(_ conversation: AIChatConversation) async {
        guard let api = apiClient else { return }
        struct SaveInput: Encodable {
            let id: String
            let title: String
            let messages: [AIChatConversation.SavedMessage]
            let createdAt: String
        }
        let input = SaveInput(
            id: conversation.id.uuidString,
            title: conversation.title,
            messages: conversation.messages,
            createdAt: ISO8601DateFormatter().string(from: conversation.createdAt)
        )
        do {
            let _: SyncSuccess = try await api.trpcMutation("ai.saveConversation", input: input)
        } catch {
            // Silently fail — local cache is the source of truth, sync is best-effort
        }
    }

    /// Delete a conversation from the backend
    private func syncDeleteConversation(id: String) async {
        guard let api = apiClient else { return }
        struct DeleteInput: Encodable { let id: String }
        let maxAttempts = 4
        for attempt in 0..<maxAttempts {
            do {
                let _: SyncSuccess = try await api.trpcMutation(
                    "ai.deleteConversation",
                    input: DeleteInput(id: id)
                )
                if let uuid = UUID(uuidString: id),
                   locallyDeletedConversationIDs.remove(uuid) != nil {
                    persistDeletedConversationIDs()
                }
                return
            } catch {
                if attempt == maxAttempts - 1 {
                    break
                }
                try? await Task.sleep(nanoseconds: UInt64(250_000_000 * (attempt + 1)))
            }
        }
    }

    /// Retry any backend deletes that are still pending confirmation.
    private func syncPendingDeletedConversations() async {
        guard !locallyDeletedConversationIDs.isEmpty else { return }
        for id in locallyDeletedConversationIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            await syncDeleteConversation(id: id.uuidString)
        }
    }

    // MARK: - Calendar Context

    /// Fetches today's and this week's events from the actor-isolated CalendarService.
    /// Stores the result in `calendarSnapshot` so `buildPayload` (sync) can use it.
    private func refreshCalendarSnapshot() async {
        guard let cal = calendarService, cal.canReadEvents() else {
            calendarSnapshot = "## Calendar\nCalendar access not granted."
            return
        }
        let today = await cal.todaysEvents()
        let cal7 = Calendar.current
        let weekEnd = cal7.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        let weekEvents = await cal.events(from: Date(), to: weekEnd)

        let todayStr = today.isEmpty ? "No events today." : today.map {
            "- \($0.title) (\(Self.shortTime($0.startDate)) – \(Self.shortTime($0.endDate)))"
        }.joined(separator: "\n")
        let weekStr = weekEvents.isEmpty ? "No events this week." : weekEvents.prefix(20).map {
            "- \($0.title) on \(Self.shortDate($0.startDate))"
        }.joined(separator: "\n")

        calendarSnapshot = """
        ## Calendar
        Today:
        \(todayStr)
        This week:
        \(weekStr)
        You CAN create calendar events via the create_calendar_event tool.
        """
    }

    // MARK: - Saved Prompts

    /// User-saved prompts, persisted to UserDefaults.
    var savedPrompts: [SavedPrompt] = [] {
        didSet { persistSavedPrompts() }
    }

    func loadSavedPrompts() {
        guard
            let data = UserDefaults.standard.data(forKey: "ai_saved_prompts"),
            let prompts = try? JSONDecoder().decode([SavedPrompt].self, from: data)
        else { return }
        savedPrompts = prompts
    }

    func addSavedPrompt(_ prompt: SavedPrompt) {
        savedPrompts.insert(prompt, at: 0)
    }

    func deleteSavedPrompt(_ prompt: SavedPrompt) {
        savedPrompts.removeAll { $0.id == prompt.id }
    }

    private func persistSavedPrompts() {
        if let data = try? JSONEncoder().encode(savedPrompts) {
            UserDefaults.standard.set(data, forKey: "ai_saved_prompts")
        }
    }

    // MARK: - Utilities

    private static func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .long
        return f.string(from: date)
    }

    private static func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }

    private static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d, h:mm a"
        return f.string(from: date)
    }

    private static func tasksToJSON(_ tasks: [TaskSummaryPayload]) -> String {
        guard
            let data = try? JSONEncoder().encode(tasks),
            let str = String(data: data, encoding: .utf8)
        else { return "[]" }
        return str
    }
}
// MARK: - Request / Response Models

struct ChatRequest: Encodable {
    let messages: [ChatMessage]
    let mentions: [MentionPayload]
    let tasks: [TaskSummaryPayload]
    let model: String
    let stream: Bool = true
}

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct TaskSummaryPayload: Encodable {
    let id: String
    let title: String
    let status: String
    let priority: String
    let dueDate: String?
    let folderName: String?
}

struct MentionPayload: Encodable {
    let id: String
    let kind: String
    let title: String
    let subtitle: String?
    let displayText: String
    let accessibilityLabel: String
}

// MARK: - Custom SSE Event Decoding (Web Search + Reasoning)

/// Custom event types sent by the backend before/alongside the OpenRouter SSE stream.
/// These events carry web search status, sources, and reasoning tokens.
private struct SSECustomEvent: Decodable {
    let type: String
    let status: String?
    let queries: [String]?
    let sources: [SSESourcePayload]?
    let content: String?
    let durationMs: Int?

    enum CodingKeys: String, CodingKey {
        case type, status, queries, sources, content
        case durationMs = "duration_ms"
    }
}

/// A web search source returned by the backend's Perplexity integration.
private struct SSESourcePayload: Decodable {
    let url: String
    let title: String
    let snippet: String
}

// MARK: - SSE Chunk Decoding

private struct SSEChunk: Decodable {
    let choices: [SSEChoice]
}

private struct SSEChoice: Decodable {
    let delta: SSEDelta
}

private struct SSEDelta: Decodable {
    let content: String?
    let toolCalls: [SSEToolCall]?

    enum CodingKeys: String, CodingKey {
        case content
        case toolCalls = "tool_calls"
    }
}

private struct SSEToolCall: Decodable {
    let function: SSEToolFunction
}

private struct SSEToolFunction: Decodable {
    let name: String
    let arguments: String
}

// MARK: - Tool Call Argument Models

struct CreateTaskArgs: Decodable {
    let title: String
    let dueDate: String?
    let folderName: String?
    let priority: String?
}

struct UpdateTaskArgs: Decodable {
    let id: String
    let title: String?
    let dueDate: String?
    let status: String?
    let priority: String?
}

struct DeleteTaskArgs: Decodable {
    let id: String
}

struct CreateCalendarEventArgs: Decodable {
    let title: String
    let startDate: String      // ISO 8601
    let endDate: String?
    let notes: String?
}

struct SendEmailArgs: Decodable {
    let to: [String]           // array of email address strings
    let subject: String
    let body: String
    let threadId: String?      // nil for new thread, set for reply
}

// MARK: - SavedPrompt

/// A user-saved or built-in prompt shown in the Prompt Library.
struct SavedPrompt: Identifiable, Codable {
    let id: UUID
    var title: String          // short display label
    var text: String           // the full prompt text sent to the AI
    var icon: String           // SF Symbol name
    var category: String       // for grouping in the library
    var isPreset: Bool         // presets can't be deleted

    init(id: UUID = UUID(), title: String, text: String, icon: String, category: String, isPreset: Bool = false) {
        self.id = id
        self.title = title
        self.text = text
        self.icon = icon
        self.category = category
        self.isPreset = isPreset
    }

    // MARK: Presets

    static let presets: [SavedPrompt] = [
        // ── Tasks ──────────────────────────────────────────────────────────────
        SavedPrompt(title: "Plan my week",
                    text: "Help me plan my week. Review my tasks and calendar, then suggest a realistic daily schedule including time blocks for deep work.",
                    icon: "calendar.badge.checkmark", category: "Tasks", isPreset: true),
        SavedPrompt(title: "Morning briefing",
                    text: "Give me a morning briefing. Summarize my tasks for today, any calendar events, and highlight anything urgent or overdue.",
                    icon: "sun.max", category: "Tasks", isPreset: true),
        SavedPrompt(title: "Top 3 priorities",
                    text: "What are my top 3 priorities right now? Consider deadlines, priority levels, and what would have the most impact.",
                    icon: "flag.fill", category: "Tasks", isPreset: true),
        SavedPrompt(title: "Break down a task",
                    text: "Take my most complex task and break it down into smaller, actionable subtasks I can complete in under 30 minutes each.",
                    icon: "list.bullet.indent", category: "Tasks", isPreset: true),
        SavedPrompt(title: "Clear overdue tasks",
                    text: "Show me all my overdue tasks and help me decide which to reschedule, delegate, or delete.",
                    icon: "exclamationmark.circle", category: "Tasks", isPreset: true),
        SavedPrompt(title: "End-of-day review",
                    text: "Let's do an end-of-day review. What did I complete today, what's left, and what should I prioritize tomorrow?",
                    icon: "moon.stars", category: "Tasks", isPreset: true),

        // ── Calendar ───────────────────────────────────────────────────────────
        SavedPrompt(title: "Find free time",
                    text: "Look at my calendar this week and find 2-hour blocks where I have no meetings or events. I want to schedule deep focus time.",
                    icon: "clock.badge.checkmark", category: "Calendar", isPreset: true),
        SavedPrompt(title: "Schedule a meeting",
                    text: "Help me prepare for my next meeting. Who's it with, what should I review beforehand, and what do I want to accomplish?",
                    icon: "person.2.fill", category: "Calendar", isPreset: true),
        SavedPrompt(title: "Create focus blocks",
                    text: "Create 2-hour focus time blocks on my calendar for tomorrow morning and the day after. Label them 'Deep Work'.",
                    icon: "brain.head.profile", category: "Calendar", isPreset: true),
        SavedPrompt(title: "Weekly overview",
                    text: "What does my week look like? Give me an overview of all my events and flag any days that look too packed.",
                    icon: "calendar", category: "Calendar", isPreset: true),

        // ── Email ──────────────────────────────────────────────────────────────
        SavedPrompt(title: "Triage inbox",
                    text: "Help me triage my inbox. Go through my recent emails and tell me which need urgent replies, which I can defer, and which can be archived.",
                    icon: "tray.and.arrow.down", category: "Email", isPreset: true),
        SavedPrompt(title: "Draft a reply",
                    text: "Help me draft a reply to the most recent unread email in my inbox. Keep it professional and concise.",
                    icon: "arrowshape.turn.up.left.fill", category: "Email", isPreset: true),
        SavedPrompt(title: "Summarize emails",
                    text: "Summarize the key points from my most recent emails. What actions do I need to take?",
                    icon: "doc.text.magnifyingglass", category: "Email", isPreset: true),
        SavedPrompt(title: "Write cold outreach",
                    text: "Help me write a cold outreach email introducing myself and my product to a potential customer. Keep it short, personal, and value-focused.",
                    icon: "envelope.badge.person.crop", category: "Email", isPreset: true),

        // ── Cross-app ──────────────────────────────────────────────────────────
        SavedPrompt(title: "Full day triage",
                    text: "Give me a complete picture of my day: tasks due, calendar events, and any emails that need attention. Then suggest what to tackle first.",
                    icon: "sparkles", category: "Cross-app", isPreset: true),
        SavedPrompt(title: "Weekly retrospective",
                    text: "Help me do a weekly retrospective. What did I accomplish this week across tasks, meetings, and emails? What should I improve next week?",
                    icon: "chart.line.uptrend.xyaxis", category: "Cross-app", isPreset: true),
        SavedPrompt(title: "Project kickoff",
                    text: "I'm starting a new project. Help me create an initial set of tasks, schedule a kickoff meeting on my calendar, and draft a brief intro email to the team.",
                    icon: "rocket", category: "Cross-app", isPreset: true),
    ]
}
