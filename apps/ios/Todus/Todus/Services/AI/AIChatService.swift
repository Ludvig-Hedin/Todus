import Foundation
import SwiftData
import Observation
import EventKit

// MARK: - AIChatService

/// Manages the AI chat conversation, streaming responses via the backend /ai/chat SSE endpoint.
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

    /// Chronologically ordered list of saved conversations (newest first).
    var savedConversations: [AIChatConversation] = []

    /// Tone instruction injected from AppServices.aiTonePreference — appended to the system prompt.
    var toneInstruction: String = ""

    private let configuration: AppConfiguration
    private let captureService: TaskCaptureService
    /// Auth service provides the Bearer token for backend API calls
    private weak var authService: AuthService?
    /// Calendar service for creating/reading EventKit events
    private var calendarService: CalendarService?
    /// Email service for reading threads and sending emails
    private weak var emailService: EmailService?
    private var streamingTask: Task<Void, Never>?

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

    init(
        configuration: AppConfiguration,
        captureService: TaskCaptureService,
        authService: AuthService? = nil,
        calendarService: CalendarService? = nil,
        emailService: EmailService? = nil
    ) {
        self.configuration = configuration
        self.captureService = captureService
        self.authService = authService
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

        // Append user message
        messages.append(AIChatMessage(role: .user, content: trimmed))

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
        // Find the last user message to replay
        guard let lastUserMessage = messages.last(where: { $0.role == .user })?.content else {
            errorMessage = nil
            return
        }
        // Remove the failed assistant placeholder if present
        if let lastMsg = messages.last, lastMsg.role == .assistant {
            messages.removeLast()
        }
        // Remove the user message too — send() will re-append it
        if let lastMsg = messages.last, lastMsg.role == .user {
            messages.removeLast()
        }
        errorMessage = nil
        send(userMessage: lastUserMessage, allTasks: allTasks, modelContext: modelContext)
    }

    /// Cancel an in-progress stream.
    func cancelStream() {
        streamingTask?.cancel()
        streamingTask = nil
        finaliseStream()
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
        messages = conversation.messages.map { saved in
            AIChatMessage(
                role: saved.role == "user" ? .user : .assistant,
                content: saved.content,
                isStreaming: false
            )
        }
        chatTitle = conversation.title
        // Already persisted — don't duplicate on next autosave
        isConversationSaved = true
    }

    /// Delete a saved conversation from history.
    func deleteConversation(_ conversation: AIChatConversation) {
        savedConversations.removeAll { $0.id == conversation.id }
        persistConversations()
    }

    // MARK: - Streaming

    private func streamResponse(
        assistantMessageID: UUID,
        allTasks: [TaskRecord],
        modelContext: ModelContext
    ) async {
        defer { finaliseStream() }

        // Pre-fetch calendar events async so buildPayload stays sync
        await refreshCalendarSnapshot()

        // Route through the main backend's /ai/chat endpoint with Bearer auth
        let baseURL = configuration.effectiveBackendURL
        let url = baseURL.appending(path: "ai/chat")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authService?.bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let payload = buildPayload(allTasks: allTasks)
        guard let body = try? JSONEncoder().encode(payload) else {
            appendError("Failed to encode request.", to: assistantMessageID)
            return
        }
        request.httpBody = body

        do {
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                appendError("Server error.", to: assistantMessageID)
                return
            }

            // Parse Server-Sent Events line by line
            for try await line in asyncBytes.lines {
                if Task.isCancelled { break }

                guard line.hasPrefix("data: ") else { continue }
                let jsonString = String(line.dropFirst(6))
                if jsonString == "[DONE]" { break }

                guard
                    let data = jsonString.data(using: .utf8),
                    let chunk = try? JSONDecoder().decode(SSEChunk.self, from: data)
                else { continue }

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
                appendError(error.localizedDescription, to: assistantMessageID)
            }
        }
    }

    // MARK: - Payload Building

    private func buildPayload(allTasks: [TaskRecord]) -> ChatRequest {
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

        // ── Calendar — fetched async before this call, cached in calendarSnapshot ──
        let calendarContext: String
        if let snap = calendarSnapshot {
            calendarContext = snap
        } else {
            calendarContext = "## Calendar\nCalendar access not granted or not yet loaded."
        }

        // ── Email ──────────────────────────────────────────────────────────────
        let emailContext: String
        if let email = emailService, !email.threads.isEmpty {
            let recent = email.threads.prefix(10).map { t in
                "- [\(t.id)] \(t.unread ? "UNREAD" : "read") from \(t.from.name.isEmpty ? t.from.email : t.from.name): \"\(t.subject)\""
            }.joined(separator: "\n")
            emailContext = """
            ## Recent Emails (inbox)
            \(recent)
            You CAN send emails via the send_email tool.
            """
        } else {
            emailContext = "## Email\nNo email threads loaded or email not connected."
        }

        // ── System prompt ──────────────────────────────────────────────────────
        let toneLine = toneInstruction.isEmpty ? "" : "\n\(toneInstruction)"
        let systemPrompt = """
        You are a powerful personal assistant embedded in Todus — a task manager, email client, and calendar app.
        Today is \(Self.formattedDate(Date())).\(toneLine)

        You have full access to the user's tasks, calendar, and email:

        \(taskContext)
        \(taskWriteNote)

        \(calendarContext)

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
        apiMessages += messages.compactMap { msg -> ChatMessage? in
            guard !msg.isStreaming || !msg.content.isEmpty else { return nil }
            let role = msg.role == .user ? "user" : "assistant"
            return ChatMessage(role: role, content: msg.content)
        }
        if apiMessages.last?.role == "assistant" && apiMessages.last?.content.isEmpty == true {
            apiMessages.removeLast()
        }

        return ChatRequest(messages: apiMessages, tasks: Array(taskSummaries), model: selectedModel)
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
                if let args = try? JSONDecoder().decode(CreateCalendarEventArgs.self, from: argsData) {
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
                if let args = try? JSONDecoder().decode(SendEmailArgs.self, from: argsData),
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

    private func finaliseStream() {
        isStreaming = false
        flushScheduled = false
        if let idx = messages.indices.last {
            // Flush any buffered tokens before marking stream as complete so the
            // last few tokens aren't lost when the stream ends mid-batch.
            if !tokenBuffer.isEmpty {
                messages[idx].content += tokenBuffer
                tokenBuffer = ""
            }
            messages[idx].isStreaming = false
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
                    content: $0.content
                )
            }
        )
        savedConversations.insert(saved, at: 0)
        // Cap history at 50 conversations
        if savedConversations.count > 50 { savedConversations.removeLast() }
        persistConversations()
    }

    private func persistConversations() {
        if let data = try? JSONEncoder().encode(savedConversations) {
            UserDefaults.standard.set(data, forKey: "ai_chat_history")
        }
    }

    private func loadPersistedConversations() {
        guard
            let data = UserDefaults.standard.data(forKey: "ai_chat_history"),
            let convs = try? JSONDecoder().decode([AIChatConversation].self, from: data)
        else { return }
        savedConversations = convs
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

private struct ChatRequest: Encodable {
    let messages: [ChatMessage]
    let tasks: [TaskSummaryPayload]
    let model: String
    let stream: Bool = true
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct TaskSummaryPayload: Encodable {
    let id: String
    let title: String
    let status: String
    let priority: String
    let dueDate: String?
    let folderName: String?
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

private struct CreateTaskArgs: Decodable {
    let title: String
    let dueDate: String?
    let folderName: String?
    let priority: String?
}

private struct UpdateTaskArgs: Decodable {
    let id: String
    let title: String?
    let dueDate: String?
    let status: String?
    let priority: String?
}

private struct DeleteTaskArgs: Decodable {
    let id: String
}

private struct CreateCalendarEventArgs: Decodable {
    let title: String
    let startDate: String      // ISO 8601
    let endDate: String?
    let notes: String?
}

private struct SendEmailArgs: Decodable {
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
