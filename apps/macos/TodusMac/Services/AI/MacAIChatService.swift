import Foundation
import Observation
import SwiftData

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

    private let backendURL: URL
    private let apiClient: TodosAPIClient
    private weak var authService: AuthService?
    private weak var emailService: EmailService?
    private var calendarService: CalendarService?
    private var streamingTask: Task<Void, Never>?

    // Token batching — flush every 40ms for smooth typewriter animation
    private var tokenBuffer = ""
    private var flushScheduled = false

    // Tracks whether the current conversation has been persisted
    private var isConversationSaved = true

    // Cached calendar context string
    private var calendarSnapshot: String? = nil

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
    func send(userMessage: String, allTasks: [TaskRecord], modelContext: ModelContext) {
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        if chatTitle == nil {
            chatTitle = String(trimmed.prefix(60))
        }

        isConversationSaved = false
        messages.append(MacChatMessage(role: .user, content: trimmed))

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
        errorMessage = nil
        isConversationSaved = true
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
                isStreaming: false
            )
        }
        chatTitle = conversation.title
        errorMessage = nil
        isConversationSaved = true
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

        // Pre-fetch calendar events so buildPayload stays sync
        await refreshCalendarSnapshot()

        let url = backendURL.appending(path: "api/ai/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authService?.bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Pre-flight: no token → fail fast
        guard authService?.bearerToken != nil else {
            appendError("Not signed in. Please log in and try again.", to: assistantMessageID)
            return
        }

        let payload = buildPayload(allTasks: allTasks, conversationMessages: requestMessages)
        guard let body = try? JSONEncoder().encode(payload) else {
            appendError("Failed to encode request.", to: assistantMessageID)
            return
        }
        request.httpBody = body

        do {
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                appendError("Invalid response from server.", to: assistantMessageID)
                return
            }
            // Capture rotated Bearer token from Better Auth's set-auth-token header
            authService?.captureRotatedToken(from: http)
            guard (200..<300).contains(http.statusCode) else {
                switch http.statusCode {
                case 401:
                    // Match iOS AIChatService: transient 401s often recover after get-session refresh.
                    if let auth = authService {
                        let refreshed = await auth.attemptSilentRefresh()
                        if refreshed {
                            appendError("Connection lost briefly. Please tap retry.", to: assistantMessageID)
                        } else {
                            auth.isSessionExpired = true
                            appendError("Session expired. Please log out and back in.", to: assistantMessageID)
                        }
                    } else {
                        appendError("Session expired. Please log out and back in.", to: assistantMessageID)
                    }
                case 503: appendError("AI service is not configured on the server (missing OPENROUTER_API_KEY).", to: assistantMessageID)
                case 502: appendError("AI provider error. The upstream AI service may be down.", to: assistantMessageID)
                default:  appendError("Server error (\(http.statusCode)).", to: assistantMessageID)
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
                if let customEvent = try? JSONDecoder().decode(MacSSECustomEvent.self, from: data),
                   !customEvent.type.isEmpty {
                    handleCustomEvent(customEvent, messageID: assistantMessageID)
                    continue
                }

                // Standard OpenRouter SSE chunk
                guard let chunk = try? JSONDecoder().decode(MacSSEChunk.self, from: data) else { continue }

                // Append delta content token-by-token
                if let delta = chunk.choices.first?.delta.content, !delta.isEmpty {
                    appendToken(delta, to: assistantMessageID)
                }

                // Process tool calls (task/calendar/email mutations)
                if let toolCalls = chunk.choices.first?.delta.toolCalls {
                    await processToolCalls(toolCalls, assistantMessageID: assistantMessageID, modelContext: modelContext)
                }
            }
        } catch {
            if !Task.isCancelled {
                appendError(error.localizedDescription, to: assistantMessageID)
            }
        }
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
            guard let argsData = toolCall.function.arguments.data(using: .utf8) else { continue }

            switch toolCall.function.name {
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
            calendarContext = "## Calendar\nCalendar access not yet loaded."
        }

        // Email
        let emailContext: String
        if let email = emailService, !email.threads.isEmpty {
            let recent = email.threads.prefix(10).map { t in
                "- [\(t.id)] \(t.unread ? "UNREAD" : "read") from \(t.from.name.isEmpty ? t.from.email : t.from.name): \"\(t.subject)\""
            }.joined(separator: "\n")
            emailContext = "## Recent Emails (inbox)\n\(recent)\nYou CAN send emails via the send_email tool."
        } else {
            emailContext = "## Email\nNo email threads loaded or email not connected."
        }

        let pageContextLine = currentPageContext.map { "\nThe user is currently viewing: \($0)." } ?? ""
        let systemPrompt = """
        You are a powerful personal assistant embedded in Todus — a task manager, email client, and calendar app (macOS desktop).
        Today is \(formattedDate(Date())).\(pageContextLine)

        You have full access to the user's tasks, calendar, and email:

        \(taskContext)
        You CAN create, update, and delete tasks via tool calls.

        \(calendarContext)
        You CAN create calendar events via the create_calendar_event tool.

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

        var apiMessages = [MacChatMessagePayload(role: "system", content: systemPrompt)]
        apiMessages += activeMessages.compactMap { msg -> MacChatMessagePayload? in
            guard !msg.isStreaming || !msg.content.isEmpty else { return nil }
            let role = msg.role == .user ? "user" : "assistant"
            return MacChatMessagePayload(role: role, content: msg.content)
        }
        if apiMessages.last?.role == "assistant" && apiMessages.last?.content.isEmpty == true {
            apiMessages.removeLast()
        }

        return MacChatRequest(
            messages: apiMessages,
            tasks: Array(taskSummaries),
            model: selectedModel
        )
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

        let todayStr = today.isEmpty ? "No events today." : today.map {
            "- \($0.title) (\(shortTime($0.startDate)) – \(shortTime($0.endDate)))"
        }.joined(separator: "\n")
        let weekStr = weekEvents.isEmpty ? "No events this week." : weekEvents.prefix(20).map {
            "- \($0.title) on \(shortDate($0.startDate))"
        }.joined(separator: "\n")

        calendarSnapshot = """
        ## Calendar
        Today:
        \(todayStr)
        This week:
        \(weekStr)
        """
    }

    // MARK: - History Persistence

    private func saveCurrentConversation() {
        guard !messages.isEmpty else { return }
        let saved = MacChatConversation(
            id: UUID(),
            title: chatTitle ?? "Untitled",
            createdAt: Date(),
            messages: messages.map {
                MacChatConversation.SavedMessage(
                    role: $0.role == .user ? "user" : "assistant",
                    content: $0.content
                )
            }
        )
        savedConversations.insert(saved, at: 0)
        if savedConversations.count > 50 { savedConversations.removeLast() }
        persistConversationsLocally()
        Task { await syncSaveConversation(saved) }
    }

    /// Persist to Keychain as a local cache (fast, survives reinstall)
    private static let chatHistoryKey = "com.todus.mac.ai.chatHistory"
    private static let deletedConversationIDsKey = "com.todus.mac.ai.deletedConversationIDs"

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
            let createdAt: String
        }
        let input = SaveInput(
            id: conversation.id.uuidString,
            title: conversation.title,
            messages: conversation.messages,
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
        reasoningDurationMs: Int? = nil
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
    var messages: [SavedMessage]

    struct SavedMessage: Codable {
        let role: String
        let content: String
    }
}

// MARK: - Request / Response Models

private struct MacChatRequest: Encodable {
    let messages: [MacChatMessagePayload]
    let tasks: [MacTaskSummary]
    let model: String
    let stream: Bool = true
}

private struct MacChatMessagePayload: Encodable {
    let role: String
    let content: String
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

private struct MacSSEToolCall: Decodable {
    let function: MacSSEToolFunction
}

private struct MacSSEToolFunction: Decodable {
    let name: String
    let arguments: String
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

private struct MacSendEmailArgs: Decodable {
    let to: [String]
    let subject: String
    let body: String
    let threadId: String?
}
