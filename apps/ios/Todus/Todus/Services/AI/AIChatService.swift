import Foundation
import SwiftData
import Observation

// MARK: - AIChatService

/// Manages the AI chat conversation, streaming responses from the chatAI Supabase edge function.
/// Maintains message history, drives real-time token streaming, and applies task mutations
/// returned by the AI as tool calls.
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

    private let configuration: AppConfiguration
    private let captureService: TaskCaptureService
    private var streamingTask: Task<Void, Never>?

    // MARK: - Token batching
    // Buffer rapid SSE tokens and flush every 40 ms so SwiftUI re-renders less often,
    // giving the typewriter animation a smoother, less-jittery feel.
    private var tokenBuffer = ""
    private var flushScheduled = false

    // Tracks whether the current conversation has been persisted so we can
    // auto-save on sheet-dismiss without creating duplicate entries.
    private var isConversationSaved = true

    init(configuration: AppConfiguration, captureService: TaskCaptureService) {
        self.configuration = configuration
        self.captureService = captureService

        // Restore persisted preferences
        self.selectedModel = UserDefaults.standard.string(forKey: "ai_selected_model")
            ?? configuration.primaryModel
        if UserDefaults.standard.object(forKey: "ai_can_read_tasks") != nil {
            self.aiCanReadTasks = UserDefaults.standard.bool(forKey: "ai_can_read_tasks")
        }
        if UserDefaults.standard.object(forKey: "ai_can_write_tasks") != nil {
            self.aiCanWriteTasks = UserDefaults.standard.bool(forKey: "ai_can_write_tasks")
        }
        loadPersistedConversations()
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

        guard
            let baseURL = configuration.supabaseURL,
            !configuration.supabaseAnonKey.isEmpty
        else {
            appendError("Backend not configured.", to: assistantMessageID)
            return
        }

        let url = baseURL
            .appending(path: "functions")
            .appending(path: "v1")
            .appending(path: configuration.chatFunctionPath)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(configuration.supabaseAnonKey)", forHTTPHeaderField: "Authorization")

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
        // Inject task context only if the user has granted read access
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
            ? "The user has \(taskSummaries.count) tasks:\n\(Self.tasksToJSON(taskSummaries))"
            : "Task access is disabled by the user."

        let writeNote = aiCanWriteTasks
            ? "When the user asks you to create, edit, or delete tasks, call the appropriate tool function."
            : "You cannot modify the user's tasks — read access only."

        let systemPrompt = """
        You are a smart task assistant embedded in a personal task manager app.
        Today is \(Self.formattedDate(Date())).

        \(taskContext)

        \(writeNote)

        FORMATTING RULES — follow these exactly:
        • NEVER use markdown tables (no | separators). Always use bullet lists (- item) for rows of data.
        • When you reference a specific task from the user's list, write [task:THAT_TASKS_UUID] on its own line. The app will render it as a native card the user can tap.
        • Use ## for section headings, **text** for bold emphasis, and - for bullet list items.
        • Leave a blank line between sections and after bullet lists.
        • Keep responses concise, action-oriented, and well-structured. Speak naturally.
        """

        var apiMessages: [ChatMessage] = [ChatMessage(role: "system", content: systemPrompt)]
        apiMessages += messages.compactMap { msg -> ChatMessage? in
            guard !msg.isStreaming || !msg.content.isEmpty else { return nil }
            let role = msg.role == .user ? "user" : "assistant"
            return ChatMessage(role: role, content: msg.content)
        }
        // Remove the last empty streaming placeholder before sending
        if apiMessages.last?.role == "assistant" && apiMessages.last?.content.isEmpty == true {
            apiMessages.removeLast()
        }

        return ChatRequest(
            messages: apiMessages,
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

    // MARK: - Utilities

    private static func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .long
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
