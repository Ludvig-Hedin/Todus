import Foundation
import Observation
import SwiftData
import OSLog
import UniformTypeIdentifiers

// MARK: - MacAIChatService

/// Full-featured AI chat service for the macOS app.
/// Streams responses via the backend /api/ai/chat SSE endpoint.
/// Supports tool calls (task CRUD, calendar, email), conversation history,
/// web search sources, reasoning tokens, retry, and model selection.
/// Feature-parity with the iOS AIChatService (minus voice and mentions).
@MainActor
@Observable
final class MacAIChatService {
    var messages: [MacChatMessage] = []
    var isStreaming: Bool = false
    var errorMessage: String?
    var chatTitle: String? = nil
    var currentConversationID: UUID? = nil
    var currentConversationFolderID: UUID? = nil

    /// Currently active model, selectable by the user at runtime.
    var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: "mac_ai_selected_model") }
    }

    /// Chronologically ordered list of saved conversations (newest first).
    var savedConversations: [MacChatConversation] = []
    /// Conversations deleted locally but not yet confirmed removed by the backend.
    private var locallyDeletedConversationIDs: Set<UUID> = []

    /// Current page/section context — injected by the view before each send.
    var currentPageContext: String? = nil

    /// Shared AI profile context loaded from settings.
    var contextAboutYou: String = ""

    /// Shared custom instructions loaded from settings.
    var customInstructions: String = ""

    private let backendURL: URL
    private let apiClient: TodosAPIClient
    private weak var authService: AuthService?
    private weak var emailService: EmailService?
    private var calendarService: CalendarService?
    private var streamingTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.todus.macos", category: "MacAIChatService")

    // Token batching — flush every 40ms for smooth typewriter animation
    private var tokenBuffer = ""
    private var flushScheduled = false

    // Tracks whether the current conversation has been persisted
    private var isConversationSaved = true

    // Cached calendar context string
    private var calendarSnapshot: String? = nil

    /// Serialized file payloads for user messages (file URLs are not always re-readable after picking).
    private var attachmentPayloadsByUserMessageId: [UUID: [MacSerializedFilePayload]] = [:]

    init(
        backendURL: URL,
        apiClient: TodosAPIClient,
        authService: AuthService,
        emailService: EmailService?,
        calendarService: CalendarService?
    ) {
        self.backendURL = backendURL
        self.apiClient = apiClient
        self.authService = authService
        self.emailService = emailService
        self.calendarService = calendarService
        self.selectedModel = UserDefaults.standard.string(forKey: "mac_ai_selected_model") ?? "openai/gpt-5.4-mini"
        loadPersistedDeletedConversationIDs()

        // Defer conversation history loading
        Task { @MainActor in loadPersistedConversations() }
    }

    // MARK: - Public API

    /// Send a user message and stream the AI response.
    func send(
        userMessage: String,
        attachmentURLs: [URL] = [],
        allTasks: [TaskRecord],
        modelContext: ModelContext
    ) {
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!trimmed.isEmpty || !attachmentURLs.isEmpty), !isStreaming else { return }

        if chatTitle == nil {
            if !trimmed.isEmpty {
                chatTitle = String(trimmed.prefix(60))
            } else if let name = attachmentURLs.first?.lastPathComponent, !name.isEmpty {
                chatTitle = String(name.prefix(60))
            }
        }

        isConversationSaved = false
        let displayNames = attachmentURLs.map { $0.lastPathComponent }
        let userMsg = MacChatMessage(role: .user, content: trimmed, attachmentFileNames: displayNames)
        messages.append(userMsg)
        if !attachmentURLs.isEmpty {
            let serialized = Self.buildSerializedAttachments(urls: attachmentURLs)
            if !serialized.isEmpty {
                attachmentPayloadsByUserMessageId[userMsg.id] = serialized
            }
        }

        let assistantID = UUID()
        messages.append(MacChatMessage(id: assistantID, role: .assistant, isStreaming: true))
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

    /// Retry the last failed assistant message.
    func retry(allTasks: [TaskRecord], modelContext: ModelContext) {
        guard !isStreaming else { return }
        guard let lastAssistant = messages.last(where: { $0.role == .assistant }) else {
            errorMessage = nil
            return
        }
        retryMessage(assistantMessageID: lastAssistant.id, allTasks: allTasks, modelContext: modelContext)
    }

    /// Whether a specific assistant message can be retried.
    func canRetry(assistantMessageID: UUID) -> Bool {
        guard !isStreaming,
              let idx = messages.firstIndex(where: { $0.id == assistantMessageID }),
              messages[idx].role == .assistant else { return false }
        return messages[..<idx].last(where: { $0.role == .user }) != nil
    }

    /// Retry a specific assistant turn in place.
    func retryMessage(assistantMessageID: UUID, allTasks: [TaskRecord], modelContext: ModelContext) {
        guard canRetry(assistantMessageID: assistantMessageID),
              let idx = messages.firstIndex(where: { $0.id == assistantMessageID }) else {
            errorMessage = nil
            return
        }

        errorMessage = nil
        isConversationSaved = false

        // Remove dependent turns after this one
        if idx + 1 < messages.count {
            messages.removeSubrange((idx + 1)..<messages.count)
        }

        messages[idx].content = ""
        messages[idx].isStreaming = true
        messages[idx].taskMutations = []
        messages[idx].sources = []
        messages[idx].searchQueries = []
        messages[idx].searchState = .none
        messages[idx].reasoningContent = ""
        messages[idx].reasoningDurationMs = nil

        isStreaming = true
        let requestMessages = Array(messages.prefix(idx))

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

    /// Drop a message (and every turn that follows it) from the conversation.
    /// Used by right-click/long-press "Edit message": the edited user turn is
    /// re-sent via `send`, so the old copy plus any dependent reply must go
    /// first to avoid stacking the new branch below the stale one.
    func truncateBefore(messageID: UUID) {
        guard !isStreaming else { return }
        guard let idx = messages.firstIndex(where: { $0.id == messageID }) else { return }
        let removedIDs = messages[idx..<messages.count].map(\.id)
        messages.removeSubrange(idx..<messages.count)
        for id in removedIDs {
            attachmentPayloadsByUserMessageId.removeValue(forKey: id)
        }
        isConversationSaved = false
        errorMessage = nil
    }

    /// Cancel an in-progress stream.
    func cancelStream() {
        streamingTask?.cancel()
        streamingTask = nil
        if let id = messages.first(where: \.isStreaming)?.id {
            finaliseStream(messageID: id)
        } else {
            isStreaming = false
            flushScheduled = false
            tokenBuffer = ""
        }
    }

    /// Save current conversation and start fresh.
    func clearHistory() {
        if !messages.isEmpty && !isConversationSaved {
            saveCurrentConversation()
        }
        if isStreaming { cancelStream() }
        messages.removeAll()
        chatTitle = nil
        currentConversationID = nil
        currentConversationFolderID = nil
        errorMessage = nil
        isConversationSaved = true
        attachmentPayloadsByUserMessageId.removeAll()
    }

    /// Auto-save when the panel is hidden. Safe to call multiple times.
    func autosave() {
        guard !messages.isEmpty, !isConversationSaved else { return }
        saveCurrentConversation()
        isConversationSaved = true
    }

    /// Restore a saved conversation.
    func loadConversation(_ conversation: MacChatConversation) {
        if isStreaming { cancelStream() }
        messages = conversation.messages.map { saved in
            MacChatMessage(
                role: saved.role == "user" ? .user : .assistant,
                content: saved.content,
                isStreaming: false,
                attachmentFileNames: saved.attachmentFileNames
            )
        }
        chatTitle = conversation.title
        currentConversationID = conversation.id
        currentConversationFolderID = conversation.folderID
        errorMessage = nil
        isConversationSaved = true
        attachmentPayloadsByUserMessageId.removeAll()
    }

    func moveConversation(_ conversation: MacChatConversation, to folderID: UUID?) {
        guard let index = savedConversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        var convo = savedConversations[index]
        convo.folderID = folderID
        savedConversations[index] = convo
        persistConversationsLocally()
        Task { await syncSaveConversation(convo) }
        if currentConversationID == convo.id {
            currentConversationFolderID = folderID
        }
    }

    /// Delete a saved conversation from history (local + backend).
    func deleteConversation(_ conversation: MacChatConversation) {
        locallyDeletedConversationIDs.insert(conversation.id)
        persistDeletedConversationIDs()
        savedConversations.removeAll { $0.id == conversation.id }
        persistConversationsLocally()
        Task { await syncDeleteConversation(id: conversation.id.uuidString) }
    }

    /// Copy the entire conversation as markdown.
    func conversationAsMarkdown() -> String {
        messages.map { msg in
            let tag = msg.role == .user ? "**User**" : "**Assistant**"
            return "\(tag)\n\(msg.content)"
        }.joined(separator: "\n\n---\n\n")
    }

    // MARK: - Streaming

    private func streamResponse(
        assistantMessageID: UUID,
        requestMessages: [MacChatMessage]? = nil,
        allTasks: [TaskRecord],
        modelContext: ModelContext
    ) async {
        defer { finaliseStream(messageID: assistantMessageID) }

        await refreshCalendarSnapshot()

        let basePayload = buildPayload(allTasks: allTasks, conversationMessages: requestMessages)

        var followUpMessages: [MacChatMessagePayload] = []
        let maxSteps = 5
        var stepsTaken = 0
        var producedAnyContent = false

        while stepsTaken < maxSteps {
            stepsTaken += 1
            let step = await runStep(
                assistantMessageID: assistantMessageID,
                basePayload: basePayload,
                extraMessages: followUpMessages,
                modelContext: modelContext
            )
            if step.hardError { return }
            if step.producedContent { producedAnyContent = true }
            if step.toolCalls.isEmpty {
                if !producedAnyContent { appendFallback(to: assistantMessageID) }
                return
            }

            let toolResults = await executeToolCalls(
                step.toolCalls,
                assistantMessageID: assistantMessageID,
                modelContext: modelContext
            )
            followUpMessages.append(
                MacChatMessagePayload.assistantWithToolCalls(
                    content: step.assistantContent,
                    toolCalls: step.toolCalls.map { $0.toChatToolCall() }
                )
            )
            followUpMessages.append(contentsOf: toolResults)
        }

        if !producedAnyContent { appendFallback(to: assistantMessageID) }
    }

    private struct MacStepResult {
        var toolCalls: [MacAccumulatedToolCall] = []
        var assistantContent: String = ""
        var producedContent: Bool = false
        var hardError: Bool = false
    }

    private func runStep(
        assistantMessageID: UUID,
        basePayload: MacChatRequest,
        extraMessages: [MacChatMessagePayload],
        modelContext: ModelContext
    ) async -> MacStepResult {
        var result = MacStepResult()

        guard authService?.bearerToken != nil else {
            appendError("Not signed in. Please log in and try again.", to: assistantMessageID)
            result.hardError = true
            return result
        }

        // Follow-up steps drop attachments because the server already inlined them
        // on step 1. Re-sending duplicates the base64 image data and re-triggers the
        // server-side web search on the same user query.
        let isFollowUp = !extraMessages.isEmpty
        var combinedMessages = basePayload.messages
        combinedMessages.append(contentsOf: extraMessages)
        let payload = MacChatRequest(
            messages: combinedMessages,
            tasks: basePayload.tasks,
            model: basePayload.model,
            stream: basePayload.stream,
            attachments: isFollowUp ? nil : basePayload.attachments
        )

        let url = backendURL.appending(path: "api/ai/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://todus.app", forHTTPHeaderField: "Origin")
        if let token = authService?.bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        guard let body = try? JSONEncoder().encode(payload) else {
            appendError("Failed to encode request.", to: assistantMessageID)
            result.hardError = true
            return result
        }
        request.httpBody = body

        var toolCallBuffer: [Int: MacAccumulatedToolCall] = [:]

        do {
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                appendError("Invalid response from server.", to: assistantMessageID)
                result.hardError = true
                return result
            }
            debugHTTPResponse(http, context: "chat stream")
            authService?.captureRotatedToken(from: http)
            guard (200..<300).contains(http.statusCode) else {
                switch http.statusCode {
                case 401:
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
                case 503: appendError("AI service is not configured on the server (missing OPENROUTER_API_KEY).", to: assistantMessageID)
                case 502: appendError("AI provider error. The upstream AI service may be down.", to: assistantMessageID)
                default:  appendError(diagnosticHTTPMessage(statusCode: http.statusCode), to: assistantMessageID)
                }
                result.hardError = true
                return result
            }

            for try await line in asyncBytes.lines {
                if Task.isCancelled { break }
                guard line.hasPrefix("data: ") else { continue }
                let jsonString = String(line.dropFirst(6))
                if jsonString == "[DONE]" { break }

                guard let data = jsonString.data(using: .utf8) else { continue }

                if let customEvent = try? JSONDecoder().decode(MacSSECustomEvent.self, from: data),
                   !customEvent.type.isEmpty {
                    handleCustomEvent(customEvent, messageID: assistantMessageID)
                    continue
                }

                guard let chunk = try? JSONDecoder().decode(MacSSEChunk.self, from: data) else { continue }
                guard let delta = chunk.choices.first?.delta else { continue }

                if let text = delta.content, !text.isEmpty {
                    result.assistantContent += text
                    result.producedContent = true
                    appendToken(text, to: assistantMessageID)
                }

                if let toolCalls = delta.toolCalls {
                    for tc in toolCalls {
                        let idx = tc.index ?? 0
                        var acc = toolCallBuffer[idx] ?? MacAccumulatedToolCall()
                        if let id = tc.id, !id.isEmpty { acc.id = id }
                        if let name = tc.function?.name, !name.isEmpty { acc.name = name }
                        if let args = tc.function?.arguments, !args.isEmpty { acc.arguments += args }
                        toolCallBuffer[idx] = acc
                    }
                }
            }
        } catch {
            if !Task.isCancelled {
                log.error("chat stream failed: \(error.localizedDescription, privacy: .public)")
                appendError(error.localizedDescription, to: assistantMessageID)
                result.hardError = true
            }
            return result
        }

        if !tokenBuffer.isEmpty,
           let idx = messages.firstIndex(where: { $0.id == assistantMessageID }) {
            messages[idx].content += tokenBuffer
            tokenBuffer = ""
        }

        result.toolCalls = toolCallBuffer.keys.sorted().compactMap { idx -> MacAccumulatedToolCall? in
            guard var tc = toolCallBuffer[idx], !tc.name.isEmpty else { return nil }
            if tc.id.isEmpty { tc.id = "call_\(UUID().uuidString)" }
            if tc.arguments.isEmpty { tc.arguments = "{}" }
            return tc
        }
        return result
    }

    private func executeToolCalls(
        _ calls: [MacAccumulatedToolCall],
        assistantMessageID: UUID,
        modelContext: ModelContext
    ) async -> [MacChatMessagePayload] {
        var out: [MacChatMessagePayload] = []
        for call in calls {
            let resultJSON = await executeSingleToolCall(
                call, assistantMessageID: assistantMessageID, modelContext: modelContext
            )
            out.append(MacChatMessagePayload.toolResult(toolCallId: call.id, name: call.name, content: resultJSON))
        }
        return out
    }

    private func executeSingleToolCall(
        _ call: MacAccumulatedToolCall,
        assistantMessageID: UUID,
        modelContext: ModelContext
    ) async -> String {
        guard let argsData = call.arguments.data(using: .utf8) else {
            return Self.encodeToolResult(success: false, message: "Invalid tool arguments")
        }

        switch call.name {
        case "create_task":
            guard let args = try? JSONDecoder().decode(MacCreateTaskArgs.self, from: argsData) else {
                return Self.encodeToolResult(success: false, message: "Invalid create_task arguments")
            }
            let dueDate = args.dueDate.flatMap { ISO8601DateFormatter().date(from: $0) }
            let task = TaskRecord(rawInput: args.title, title: args.title)
            task.dueDate = dueDate
            if let priorityStr = args.priority {
                task.priority = AppTaskPriority(rawValue: priorityStr) ?? .none
            }
            modelContext.insert(task)
            do {
                try modelContext.save()
            } catch {
                modelContext.delete(task)
                AppLogger.shared.log("[MacAIChatService] Failed to save created task: \(error)")
                return Self.encodeToolResult(success: false, message: "Failed to save task: \(error.localizedDescription)")
            }
            appendMutation(MacTaskMutation(action: .create, title: args.title, dueDate: dueDate), to: assistantMessageID)
            return Self.encodeToolResult(success: true, message: "Task '\(args.title)' created")

        case "update_task":
            guard let args = try? JSONDecoder().decode(MacUpdateTaskArgs.self, from: argsData),
                  let taskID = UUID(uuidString: args.id) else {
                return Self.encodeToolResult(success: false, message: "Invalid update_task arguments")
            }
            applyUpdateTask(taskID: taskID, args: args, modelContext: modelContext)
            appendMutation(MacTaskMutation(action: .update, taskID: taskID, title: args.title), to: assistantMessageID)
            return Self.encodeToolResult(success: true, message: "Task updated")

        case "delete_task":
            guard let args = try? JSONDecoder().decode(MacDeleteTaskArgs.self, from: argsData),
                  let taskID = UUID(uuidString: args.id) else {
                return Self.encodeToolResult(success: false, message: "Invalid delete_task arguments")
            }
            applyDeleteTask(taskID: taskID, modelContext: modelContext)
            appendMutation(MacTaskMutation(action: .delete, taskID: taskID), to: assistantMessageID)
            return Self.encodeToolResult(success: true, message: "Task deleted")

        case "create_calendar_event":
            guard let args = try? JSONDecoder().decode(MacCreateCalendarEventArgs.self, from: argsData) else {
                return Self.encodeToolResult(success: false, message: "Invalid create_calendar_event arguments")
            }
            let iso = ISO8601DateFormatter()
            guard let startDate = iso.date(from: args.startDate) else {
                return Self.encodeToolResult(success: false, message: "Invalid startDate — expected ISO 8601")
            }
            guard let cal = calendarService, cal.canCreateEvents() else {
                return Self.encodeToolResult(success: false, message: "Calendar permission not granted")
            }
            let endDate = args.endDate.flatMap { iso.date(from: $0) }
            do {
                try await cal.createEvent(title: args.title, startDate: startDate, endDate: endDate)
                appendMutation(MacTaskMutation(action: .create, title: "📅 \(args.title)"), to: assistantMessageID)
                return Self.encodeToolResult(success: true, message: "Calendar event '\(args.title)' created")
            } catch {
                return Self.encodeToolResult(success: false, message: "Failed to create event: \(error.localizedDescription)")
            }

        case "update_calendar_event":
            guard let args = try? JSONDecoder().decode(MacUpdateCalendarEventArgs.self, from: argsData) else {
                return Self.encodeToolResult(success: false, message: "Invalid update_calendar_event arguments")
            }
            guard let cal = calendarService else {
                return Self.encodeToolResult(success: false, message: "Calendar not available")
            }
            let iso = ISO8601DateFormatter()
            let start = args.startDate.flatMap { iso.date(from: $0) }
            let end = args.endDate.flatMap { iso.date(from: $0) }
            do {
                try await cal.updateEvent(
                    identifier: args.id,
                    title: args.title,
                    startDate: start,
                    endDate: end,
                    notes: args.notes
                )
                appendMutation(MacTaskMutation(action: .update, title: "📅 \(args.title ?? "Event")"), to: assistantMessageID)
                return Self.encodeToolResult(success: true, message: "Event updated")
            } catch {
                return Self.encodeToolResult(success: false, message: "Failed to update event: \(error.localizedDescription)")
            }

        case "delete_calendar_event":
            guard let args = try? JSONDecoder().decode(MacDeleteCalendarEventArgs.self, from: argsData) else {
                return Self.encodeToolResult(success: false, message: "Invalid delete_calendar_event arguments")
            }
            guard let cal = calendarService else {
                return Self.encodeToolResult(success: false, message: "Calendar not available")
            }
            do {
                try await cal.deleteEvent(identifier: args.id)
                appendMutation(MacTaskMutation(action: .delete, title: "📅 Event removed"), to: assistantMessageID)
                return Self.encodeToolResult(success: true, message: "Event deleted")
            } catch {
                return Self.encodeToolResult(success: false, message: "Failed to delete event: \(error.localizedDescription)")
            }

        case "send_email":
            guard let args = try? JSONDecoder().decode(MacSendEmailArgs.self, from: argsData),
                  let email = emailService else {
                return Self.encodeToolResult(success: false, message: "Invalid send_email arguments or email unavailable")
            }
            let draft = EmailDraft(
                to: args.to,
                subject: args.subject,
                body: args.body,
                replyToThreadId: args.threadId
            )
            let sent = await email.sendEmail(draft)
            if sent {
                appendMutation(MacTaskMutation(action: .create, title: "✉️ Sent: \(args.subject)"), to: assistantMessageID)
                return Self.encodeToolResult(success: true, message: "Email sent: \(args.subject)")
            } else {
                return Self.encodeToolResult(success: false, message: "Failed to send email")
            }

        default:
            return Self.encodeToolResult(success: false, message: "Unknown tool '\(call.name)'")
        }
    }

    private static func encodeToolResult(success: Bool, message: String) -> String {
        struct ToolResult: Encodable { let success: Bool; let message: String }
        if let data = try? JSONEncoder().encode(ToolResult(success: success, message: message)),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{\"success\":\(success),\"message\":\"(encoding failed)\"}"
    }

    private func appendFallback(to messageID: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == messageID }) else { return }
        if messages[idx].content.isEmpty {
            messages[idx].content = "Done."
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

    private func handleCustomEvent(_ event: MacSSECustomEvent, messageID: UUID) {
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
                MacWebSource(url: src.url, title: src.title, snippet: src.snippet)
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

    // MARK: - Tool Call Processing

    private func processToolCalls(
        _ toolCalls: [MacSSEToolCall],
        assistantMessageID: UUID,
        modelContext: ModelContext
    ) async {
        for toolCall in toolCalls {
            guard let fn = toolCall.function,
                  let argsStr = fn.arguments,
                  let argsData = argsStr.data(using: .utf8) else { continue }

            switch fn.name ?? "" {
            case "create_task":
                if let args = try? JSONDecoder().decode(MacCreateTaskArgs.self, from: argsData) {
                    let dueDate = args.dueDate.flatMap { ISO8601DateFormatter().date(from: $0) }
                    // Create task in SwiftData
                    let task = TaskRecord(rawInput: args.title, title: args.title)
                    task.dueDate = dueDate
                    if let priorityStr = args.priority {
                        task.priority = AppTaskPriority(rawValue: priorityStr) ?? .none
                    }
                    modelContext.insert(task)
                    try? modelContext.save()
                    let mutation = MacTaskMutation(action: .create, title: args.title, dueDate: dueDate)
                    appendMutation(mutation, to: assistantMessageID)
                }

            case "update_task":
                if let args = try? JSONDecoder().decode(MacUpdateTaskArgs.self, from: argsData),
                   let taskID = UUID(uuidString: args.id) {
                    applyUpdateTask(taskID: taskID, args: args, modelContext: modelContext)
                    let mutation = MacTaskMutation(action: .update, taskID: taskID, title: args.title)
                    appendMutation(mutation, to: assistantMessageID)
                }

            case "delete_task":
                if let args = try? JSONDecoder().decode(MacDeleteTaskArgs.self, from: argsData),
                   let taskID = UUID(uuidString: args.id) {
                    applyDeleteTask(taskID: taskID, modelContext: modelContext)
                    let mutation = MacTaskMutation(action: .delete, taskID: taskID)
                    appendMutation(mutation, to: assistantMessageID)
                }

            case "create_calendar_event":
                if let args = try? JSONDecoder().decode(MacCreateCalendarEventArgs.self, from: argsData) {
                    let iso = ISO8601DateFormatter()
                    if let startDate = iso.date(from: args.startDate),
                       let cal = calendarService, cal.canCreateEvents() {
                        let endDate = args.endDate.flatMap { iso.date(from: $0) }
                        // CalendarService is an actor — createEvent requires await
                        try? await cal.createEvent(title: args.title, startDate: startDate, endDate: endDate)
                        let mutation = MacTaskMutation(action: .create, title: "📅 \(args.title)")
                        appendMutation(mutation, to: assistantMessageID)
                    }
                }

            case "send_email":
                if let args = try? JSONDecoder().decode(MacSendEmailArgs.self, from: argsData),
                   let email = emailService {
                    let draft = EmailDraft(
                        to: args.to,
                        subject: args.subject,
                        body: args.body,
                        replyToThreadId: args.threadId
                    )
                    Task { await email.sendEmail(draft) }
                    let mutation = MacTaskMutation(action: .create, title: "✉️ Sent: \(args.subject)")
                    appendMutation(mutation, to: assistantMessageID)
                }

            default:
                break
            }
        }
    }

    private func applyUpdateTask(taskID: UUID, args: MacUpdateTaskArgs, modelContext: ModelContext) {
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
        modelContext.delete(task)
        try? modelContext.save()
    }

    // MARK: - Payload Building

    private static let maxAttachmentBytes = 5 * 1024 * 1024
    private static let maxTotalAttachmentBytes = 12 * 1024 * 1024

    private static func buildSerializedAttachments(urls: [URL]) -> [MacSerializedFilePayload] {
        var total = 0
        var out: [MacSerializedFilePayload] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            if data.count > maxAttachmentBytes { continue }
            if total + data.count > maxTotalAttachmentBytes { break }
            total += data.count
            let name = url.lastPathComponent
            var mime = "application/octet-stream"
            let ext = url.pathExtension.lowercased()
            if let ut = UTType(filenameExtension: ext), let m = ut.preferredMIMEType {
                mime = m
            }
            var lastModMs = 0
            if let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
               let d = vals.contentModificationDate {
                lastModMs = Int(d.timeIntervalSince1970 * 1000)
            }
            out.append(
                MacSerializedFilePayload(
                    name: name.isEmpty ? "attachment" : name,
                    type: mime,
                    size: data.count,
                    lastModified: lastModMs,
                    base64: data.base64EncodedString()
                )
            )
        }
        return out
    }

    private func buildPayload(
        allTasks: [TaskRecord],
        conversationMessages: [MacChatMessage]? = nil
    ) -> MacChatRequest {
        let activeMessages = conversationMessages ?? messages

        // Tasks
        let taskSummaries = allTasks.prefix(100).map { task in
            MacTaskSummary(
                id: task.id.uuidString,
                title: task.title,
                status: task.status.rawValue,
                priority: task.priority.rawValue,
                dueDate: task.dueDate.map { ISO8601DateFormatter().string(from: $0) },
                folderName: task.folder?.name
            )
        }
        let taskContext = "## Tasks (\(taskSummaries.count) total)\n\(tasksToJSON(taskSummaries))"

        // Calendar
        let calendarContext: String
        if let snap = calendarSnapshot {
            calendarContext = snap
        } else {
            calendarContext = "## Calendar\nCalendar is not connected. Inform the user that their calendar is not connected and they need to grant Calendar permission in macOS System Settings to use calendar features."
        }

        // Email
        let emailContext: String
        if let email = emailService, !email.threads.isEmpty {
            let recent = email.threads.prefix(10).map { t in
                "- [\(t.id)] \(t.unread ? "UNREAD" : "read") from \(t.from.name.isEmpty ? t.from.email : t.from.name): \"\(t.subject)\""
            }.joined(separator: "\n")
            emailContext = "## Recent Emails (inbox)\n\(recent)\nYou CAN send emails via the send_email tool."
        } else {
            emailContext = "## Email\nEmail is not connected. Inform the user that their email inbox is not connected and they need to connect an email account in settings."
        }

        let sharedAIProfilePrompt = Self.buildAIProfilePrompt(
            contextAboutYou: contextAboutYou,
            customInstructions: customInstructions
        )
        let pageContextLine = currentPageContext.map { "\nThe user is currently viewing: \($0)." } ?? ""
        let profileLine = sharedAIProfilePrompt.isEmpty ? "" : "\(sharedAIProfilePrompt)\n\n"
        let systemPrompt = """
        \(profileLine)You are a powerful personal assistant embedded in Todus — a task manager, email client, and calendar app (macOS desktop).
        Today is \(formattedDate(Date())).\(pageContextLine)

        You have full access to the user's tasks, calendar, and email:

        \(taskContext)
        You CAN create, update, and delete tasks via tool calls.

        \(calendarContext)
        You CAN create, update, and delete calendar events via create_calendar_event, update_calendar_event, and delete_calendar_event. Pass the bracketed event identifier as `id` when updating or deleting.

        \(emailContext)

        CAPABILITIES — you can:
        • Read, create, update, and delete tasks (use create_task, update_task, delete_task tools)
        • Read calendar events and create, update, or delete them (calendar tools above)
        • Read email threads and send new emails or replies (use send_email tool)

        FORMATTING RULES — follow these exactly:
        • NEVER use markdown tables. Always use bullet lists (- item) for tabular data.
        • When referencing a task, write [task:UUID] on its own line — the app renders it as a native card.
        • Use ## for section headings, **bold** for emphasis, - for bullets.
        • Leave a blank line between sections and after bullet lists.
        • Be concise, action-oriented, and natural. Don't over-explain.
        """

        var apiMessages = [MacChatMessagePayload(role: "system", content: systemPrompt)]
        apiMessages += activeMessages.compactMap { msg -> MacChatMessagePayload? in
            guard !msg.isStreaming || !msg.content.isEmpty else { return nil }
            let role = msg.role == .user ? "user" : "assistant"
            return MacChatMessagePayload(role: role, content: msg.content)
        }
        if apiMessages.last?.role == "assistant", (apiMessages.last?.content ?? "").isEmpty {
            apiMessages.removeLast()
        }

        let attachmentPayload: [MacSerializedFilePayload]? = {
            guard let lastUser = activeMessages.reversed().first(where: { $0.role == .user })
            else { return nil }
            let cached = attachmentPayloadsByUserMessageId[lastUser.id]
            if let cached, !cached.isEmpty { return cached }
            return nil
        }()

        return MacChatRequest(
            messages: apiMessages,
            tasks: Array(taskSummaries),
            model: selectedModel,
            stream: true,
            attachments: attachmentPayload
        )
    }

    private static func buildAIProfilePrompt(contextAboutYou: String, customInstructions: String) -> String {
        var sections: [String] = []

        let context = contextAboutYou.trimmingCharacters(in: .whitespacesAndNewlines)
        if !context.isEmpty {
            sections.append("## Context about you\n\(context)")
        }

        let instructions = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !instructions.isEmpty {
            sections.append("## Custom instructions\n\(instructions)")
        }

        return sections.joined(separator: "\n\n")
    }
    // MARK: - Token & Message Helpers

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

    private func appendMutation(_ mutation: MacTaskMutation, to messageID: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[idx].taskMutations.append(mutation)
    }

    private func finaliseStream(messageID: UUID) {
        isStreaming = false
        flushScheduled = false
        if let idx = messages.firstIndex(where: { $0.id == messageID }) {
            if !tokenBuffer.isEmpty {
                messages[idx].content += tokenBuffer
                tokenBuffer = ""
            }
            messages[idx].isStreaming = false
        }
    }

    // MARK: - Calendar Context

    private func refreshCalendarSnapshot() async {
        guard let cal = calendarService, cal.canReadEvents() else {
            calendarSnapshot = "## Calendar\nCalendar access not granted."
            return
        }
        // CalendarService is an actor — calls require await
        let today = await cal.todaysEvents()
        let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        let weekEvents = await cal.events(from: Date(), to: weekEnd)

        // Include event identifiers so the AI can reference them in update/delete tool calls.
        // Without `[id]`, the model has no handle to pass as `id` to update_calendar_event /
        // delete_calendar_event — those tools become effectively unreachable.
        let todayStr = today.isEmpty ? "No events today." : today.map {
            "- [\($0.id)] \($0.title) (\(shortTime($0.startDate)) – \(shortTime($0.endDate)))"
        }.joined(separator: "\n")
        let weekStr = weekEvents.isEmpty ? "No events this week." : weekEvents.prefix(20).map {
            "- [\($0.id)] \($0.title) on \(shortDate($0.startDate))"
        }.joined(separator: "\n")

        calendarSnapshot = """
        ## Calendar
        Today:
        \(todayStr)
        This week:
        \(weekStr)
        You CAN create, update, and delete calendar events via the create_calendar_event, update_calendar_event, and delete_calendar_event tools. Pass the bracketed identifier as `id` when updating or deleting.
        """
    }

    // MARK: - History Persistence

    private func saveCurrentConversation() {
        guard !messages.isEmpty else { return }
        let saved = MacChatConversation(
            id: UUID(),
            title: chatTitle ?? "Untitled",
            createdAt: Date(),
            folderID: currentConversationFolderID,
            messages: messages.map {
                MacChatConversation.SavedMessage(
                    role: $0.role == .user ? "user" : "assistant",
                    content: $0.content,
                    attachmentFileNames: $0.attachmentFileNames
                )
            }
        )
        savedConversations.insert(saved, at: 0)
        currentConversationID = saved.id
        if savedConversations.count > 50 { savedConversations.removeLast() }
        persistConversationsLocally()
        Task { await syncSaveConversation(saved) }
    }

    /// Persist to Keychain as a local cache (fast, survives reinstall)
    private static let chatHistoryKey = "com.todus.mac.ai.chatHistory"
    private static let deletedConversationIDsKey = "com.todus.mac.ai.deletedConversationIDs"

    private func persistConversationsLocally() {
        guard let data = try? JSONEncoder().encode(savedConversations) else { return }
        if !KeychainHelper.saveData(key: Self.chatHistoryKey, value: data) {
            log.error("Failed to persist macOS AI chat history to Keychain")
        }
    }

    private func persistDeletedConversationIDs() {
        guard let data = try? JSONEncoder().encode(Array(locallyDeletedConversationIDs)) else { return }
        if !KeychainHelper.saveData(key: Self.deletedConversationIDsKey, value: data) {
            log.error("Failed to persist deleted macOS AI conversation IDs to Keychain")
        }
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
           let convs = try? JSONDecoder().decode([MacChatConversation].self, from: data) {
            savedConversations = convs
        }
        // Migrate from UserDefaults (old location) if present
        else if let data = UserDefaults.standard.data(forKey: "mac_ai_chat_history"),
                let convs = try? JSONDecoder().decode([MacChatConversation].self, from: data) {
            savedConversations = convs
            persistConversationsLocally()
            UserDefaults.standard.removeObject(forKey: "mac_ai_chat_history")
        }
        // Then fetch from backend to get conversations from other devices
        Task { await syncLoadConversations() }
    }

    // MARK: - Backend Sync

    private struct ConversationListResponse: Decodable {
        let conversations: [RemoteConversation]
    }

    private struct RemoteConversation: Decodable {
        let id: String
        let folderId: String?
        let title: String
        let createdAt: Date
        let updatedAt: Date
        let messages: [MacChatConversation.SavedMessage]?
    }

    private struct SyncSuccess: Decodable {
        let success: Bool
    }

    /// Fetch conversation list from backend and merge with local cache
    private func syncLoadConversations() async {
        let preSyncIDs = Set(savedConversations.map { $0.id })
        let preSyncDeletedIDs = locallyDeletedConversationIDs
        do {
            let response: ConversationListResponse = try await apiClient.trpcQuery("ai.listConversations")
            let remoteConvos = response.conversations
            let deletedIDsToSkip = preSyncDeletedIDs.union(locallyDeletedConversationIDs)
            var mergedByID = Dictionary(uniqueKeysWithValues: savedConversations.map { ($0.id, $0) })
            for remote in remoteConvos {
                guard let uuid = UUID(uuidString: remote.id),
                      !deletedIDsToSkip.contains(uuid) else {
                    continue
                }
                if let full = await fetchFullConversation(id: remote.id) {
                    guard !deletedIDsToSkip.contains(full.id) else { continue }
                    mergedByID[full.id] = full
                }
            }
            var merged = Array(mergedByID.values)
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
            // Backend unreachable — local cache is still available
            await syncPendingDeletedConversations()
        }
    }

    private func fetchFullConversation(id: String) async -> MacChatConversation? {
        struct GetInput: Encodable { let id: String }
        do {
            let remote: RemoteConversation = try await apiClient.trpcQuery("ai.getConversation", input: GetInput(id: id))
            guard let uuid = UUID(uuidString: remote.id) else { return nil }
            return MacChatConversation(
                id: uuid,
                title: remote.title,
                createdAt: remote.createdAt,
                folderID: remote.folderId.flatMap(UUID.init(uuidString:)),
                messages: remote.messages ?? []
            )
        } catch {
            return nil
        }
    }

    private func syncSaveConversation(_ conversation: MacChatConversation) async {
        struct SaveInput: Encodable {
            let id: String
            let title: String
            let messages: [MacChatConversation.SavedMessage]
            let folderId: String?
            let createdAt: String
        }
        let input = SaveInput(
            id: conversation.id.uuidString,
            title: conversation.title,
            messages: conversation.messages,
            folderId: conversation.folderID?.uuidString,
            createdAt: ISO8601DateFormatter().string(from: conversation.createdAt)
        )
        do {
            let _: SyncSuccess = try await apiClient.trpcMutation("ai.saveConversation", input: input)
        } catch {
            // Silently fail — local cache is the source of truth
        }
    }

    private func syncDeleteConversation(id: String) async {
        struct DeleteInput: Encodable { let id: String }
        let maxAttempts = 4
        for attempt in 0..<maxAttempts {
            do {
                let _: SyncSuccess = try await apiClient.trpcMutation(
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

    private func syncPendingDeletedConversations() async {
        guard !locallyDeletedConversationIDs.isEmpty else { return }
        for id in locallyDeletedConversationIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            await syncDeleteConversation(id: id.uuidString)
        }
    }

    // MARK: - Utilities

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .long; return f.string(from: date)
    }
    private func shortTime(_ date: Date) -> String {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f.string(from: date)
    }
    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE MMM d, h:mm a"; return f.string(from: date)
    }
    private func tasksToJSON(_ tasks: [MacTaskSummary]) -> String {
        guard let data = try? JSONEncoder().encode(tasks),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }
}

// MARK: - Chat Message Model

struct MacChatMessage: Identifiable {
    enum Role { case user, assistant }

    /// Web search phase for progressive UI rendering.
    enum SearchPhase { case none, searching, complete }

    let id: UUID
    var role: Role
    var content: String
    var isStreaming: Bool
    /// Task mutations the AI requested (create / update / delete)
    var taskMutations: [MacTaskMutation]
    /// Web search sources cited in this response
    var sources: [MacWebSource]
    /// Search queries the backend executed
    var searchQueries: [String]
    /// Current search phase
    var searchState: SearchPhase
    /// Reasoning/thinking text streamed separately from main content
    var reasoningContent: String
    /// Duration of reasoning phase in ms
    var reasoningDurationMs: Int?
    /// Display names for files attached to this user message
    var attachmentFileNames: [String]

    init(
        id: UUID = UUID(),
        role: Role,
        content: String = "",
        isStreaming: Bool = false,
        taskMutations: [MacTaskMutation] = [],
        sources: [MacWebSource] = [],
        searchQueries: [String] = [],
        searchState: SearchPhase = .none,
        reasoningContent: String = "",
        reasoningDurationMs: Int? = nil,
        attachmentFileNames: [String] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
        self.taskMutations = taskMutations
        self.sources = sources
        self.searchQueries = searchQueries
        self.searchState = searchState
        self.reasoningContent = reasoningContent
        self.reasoningDurationMs = reasoningDurationMs
        self.attachmentFileNames = attachmentFileNames
    }
}

// MARK: - Task Mutation

struct MacTaskMutation: Identifiable {
    enum Action: String { case create, update, delete }

    let id: UUID
    let action: Action
    var taskID: UUID?
    var title: String?
    var dueDate: Date?

    init(id: UUID = UUID(), action: Action, taskID: UUID? = nil, title: String? = nil, dueDate: Date? = nil) {
        self.id = id; self.action = action; self.taskID = taskID; self.title = title; self.dueDate = dueDate
    }
}

// MARK: - Web Source

struct MacWebSource: Identifiable {
    let id: UUID
    let url: String
    let title: String
    let snippet: String
    var domain: String { URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? url }

    init(id: UUID = UUID(), url: String, title: String, snippet: String) {
        self.id = id; self.url = url; self.title = title; self.snippet = snippet
    }
}

// MARK: - Conversation History

struct MacChatConversation: Identifiable, Codable {
    let id: UUID
    var title: String
    let createdAt: Date
    var folderID: UUID?
    var messages: [SavedMessage]

    struct SavedMessage: Codable {
        let role: String
        let content: String
        var attachmentFileNames: [String]

        init(role: String, content: String, attachmentFileNames: [String] = []) {
            self.role = role
            self.content = content
            self.attachmentFileNames = attachmentFileNames
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            role = try c.decode(String.self, forKey: .role)
            content = try c.decode(String.self, forKey: .content)
            attachmentFileNames = try c.decodeIfPresent([String].self, forKey: .attachmentFileNames) ?? []
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(role, forKey: .role)
            try c.encode(content, forKey: .content)
            try c.encode(attachmentFileNames, forKey: .attachmentFileNames)
        }

        private enum CodingKeys: String, CodingKey {
            case role, content, attachmentFileNames
        }
    }
}

// MARK: - Request / Response Models

private struct MacSerializedFilePayload: Encodable {
    let name: String
    let type: String
    let size: Int
    let lastModified: Int
    let base64: String
}

private struct MacChatRequest: Encodable {
    let messages: [MacChatMessagePayload]
    let tasks: [MacTaskSummary]
    let model: String
    let stream: Bool
    let attachments: [MacSerializedFilePayload]?

    enum CodingKeys: String, CodingKey {
        case messages, tasks, model, stream, attachments
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(messages, forKey: .messages)
        try c.encode(tasks, forKey: .tasks)
        try c.encode(model, forKey: .model)
        try c.encode(stream, forKey: .stream)
        if let attachments, !attachments.isEmpty {
            try c.encode(attachments, forKey: .attachments)
        }
    }
}

/// OpenAI-style chat message for `/api/ai/chat` — supports text, assistant tool calls, and tool results.
private struct MacChatMessagePayload: Encodable {
    let role: String
    let content: String?
    let toolCalls: [MacChatToolCall]?
    let toolCallId: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case role, content, name
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
    }

    init(
        role: String,
        content: String? = nil,
        toolCalls: [MacChatToolCall]? = nil,
        toolCallId: String? = nil,
        name: String? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.name = name
    }

    static func assistantWithToolCalls(content: String, toolCalls: [MacChatToolCall]) -> MacChatMessagePayload {
        // Use nil (omitted in JSON) when content is empty — some OpenRouter-routed
        // models (notably Anthropic via OpenRouter) reject `"content": ""` paired with
        // `tool_calls`. nil → field is dropped → universally accepted as tool-only.
        MacChatMessagePayload(
            role: "assistant",
            content: content.isEmpty ? nil : content,
            toolCalls: toolCalls
        )
    }

    static func toolResult(toolCallId: String, name: String, content: String) -> MacChatMessagePayload {
        MacChatMessagePayload(role: "tool", content: content, toolCallId: toolCallId, name: name)
    }
}

private struct MacChatToolCall: Encodable {
    let id: String
    let type: String
    let function: MacChatToolFunction

    init(id: String, name: String, arguments: String) {
        self.id = id
        self.type = "function"
        self.function = MacChatToolFunction(name: name, arguments: arguments)
    }
}

private struct MacChatToolFunction: Encodable {
    let name: String
    let arguments: String
}

/// Accumulator for a tool call streamed across multiple SSE chunks.
private struct MacAccumulatedToolCall {
    var id: String = ""
    var name: String = ""
    var arguments: String = ""

    func toChatToolCall() -> MacChatToolCall {
        MacChatToolCall(id: id, name: name, arguments: arguments)
    }
}

private struct MacTaskSummary: Encodable {
    let id: String
    let title: String
    let status: String
    let priority: String
    let dueDate: String?
    let folderName: String?
}

// MARK: - SSE Decoding

private struct MacSSECustomEvent: Decodable {
    let type: String
    let status: String?
    let queries: [String]?
    let sources: [MacSSESourcePayload]?
    let content: String?
    let durationMs: Int?

    enum CodingKeys: String, CodingKey {
        case type, status, queries, sources, content
        case durationMs = "duration_ms"
    }
}

private struct MacSSESourcePayload: Decodable {
    let url: String
    let title: String
    let snippet: String
}

private struct MacSSEChunk: Decodable {
    let choices: [MacSSEChoice]
}

private struct MacSSEChoice: Decodable {
    let delta: MacSSEDelta
}

private struct MacSSEDelta: Decodable {
    let content: String?
    let toolCalls: [MacSSEToolCall]?

    enum CodingKeys: String, CodingKey {
        case content
        case toolCalls = "tool_calls"
    }
}

/// Streaming tool_call fragment: fields are optional because the stream splits deltas.
private struct MacSSEToolCall: Decodable {
    let index: Int?
    let id: String?
    let function: MacSSEToolFunction?
}

private struct MacSSEToolFunction: Decodable {
    let name: String?
    let arguments: String?
}

// MARK: - Tool Call Argument Models

private struct MacCreateTaskArgs: Decodable {
    let title: String
    let dueDate: String?
    let folderName: String?
    let priority: String?
}

private struct MacUpdateTaskArgs: Decodable {
    let id: String
    let title: String?
    let dueDate: String?
    let status: String?
    let priority: String?
}

private struct MacDeleteTaskArgs: Decodable {
    let id: String
}

private struct MacCreateCalendarEventArgs: Decodable {
    let title: String
    let startDate: String
    let endDate: String?
    let notes: String?
}

private struct MacUpdateCalendarEventArgs: Decodable {
    let id: String
    let title: String?
    let startDate: String?
    let endDate: String?
    let notes: String?
}

private struct MacDeleteCalendarEventArgs: Decodable {
    let id: String
}

private struct MacSendEmailArgs: Decodable {
    let to: [String]
    let subject: String
    let body: String
    let threadId: String?
}
