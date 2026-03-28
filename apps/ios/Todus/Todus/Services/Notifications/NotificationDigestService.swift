import Foundation
import SwiftData

// MARK: - Notification Item Model

enum NotificationType: String, Codable, CaseIterable {
    case taskDue = "task_due"
    case event = "event"
    case importantEmail = "important_email"
    case reminder = "reminder"

    var displayName: String {
        switch self {
        case .taskDue: return "Tasks Due"
        case .event: return "Events"
        case .importantEmail: return "Important Emails"
        case .reminder: return "Reminders"
        }
    }

    var iconName: String {
        switch self {
        case .taskDue: return "checklist"
        case .event: return "calendar"
        case .importantEmail: return "envelope.fill"
        case .reminder: return "bell.fill"
        }
    }
}

struct NotificationItem: Identifiable, Codable {
    let id: String
    let type: NotificationType
    let title: String
    let description: String
    let priority: String // high, medium, low
    let relatedId: String? // task UUID, thread ID, etc.

    enum CodingKeys: String, CodingKey {
        case id, type, title, description, priority
        case relatedId = "related_id"
    }
}

// MARK: - Notification Digest Service

/// Generates an AI-powered notification digest by sending local app data
/// (tasks, calendar events, emails) to the backend /ai/chat endpoint.
/// Uses non-streaming mode for simpler JSON parsing.
@MainActor
@Observable
final class NotificationDigestService {
    var items: [NotificationItem] = []
    var isLoading = false
    var errorMessage: String?

    private weak var authService: AuthService?
    private let configuration: AppConfiguration

    init(configuration: AppConfiguration, authService: AuthService?) {
        self.configuration = configuration
        self.authService = authService
    }

    /// Fetches an AI-generated notification digest from the user's current data.
    func fetchDigest(
        tasks: [TaskRecord],
        events: [CalendarEvent],
        emailThreads: [EmailThread]
    ) async {
        isLoading = true
        errorMessage = nil
        items = []

        defer { isLoading = false }

        // Build context strings from local data
        let now = Date()
        let dateFormatter = ISO8601DateFormatter()
        let readableDateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return f
        }()

        // Tasks context — focus on incomplete tasks with due dates
        let taskLines: [String] = tasks.prefix(50).compactMap { task in
            guard !task.completed else { return nil }
            let duePart: String
            if let dueDate = task.dueDate {
                duePart = " (due: \(readableDateFormatter.string(from: dueDate)))"
            } else {
                duePart = ""
            }
            return "- [\(task.id)] \"\(task.title)\" status:\(task.status.rawValue) priority:\(task.priority.rawValue)\(duePart)"
        }
        let tasksBlock = taskLines.isEmpty
            ? "No tasks."
            : taskLines.joined(separator: "\n")

        // Events context
        let eventLines: [String] = events.prefix(20).map { event in
            let timePart = event.isAllDay
                ? "all day"
                : "\(readableDateFormatter.string(from: event.startDate)) – \(readableDateFormatter.string(from: event.endDate))"
            return "- \"\(event.title)\" \(timePart)"
        }
        let eventsBlock = eventLines.isEmpty
            ? "No calendar events today."
            : eventLines.joined(separator: "\n")

        // Email context
        let emailLines: [String] = emailThreads.prefix(15).map { thread in
            let unreadMark = thread.unread ? "UNREAD" : "read"
            return "- [\(thread.id)] \(unreadMark) from \(thread.from.name.isEmpty ? thread.from.email : thread.from.name): \"\(thread.subject)\" – \(thread.snippet)"
        }
        let emailsBlock = emailLines.isEmpty
            ? "No emails loaded."
            : emailLines.joined(separator: "\n")

        // System prompt asking AI to return structured JSON notifications
        let systemPrompt = """
        You are a notification center AI for Todus — a personal productivity app with tasks, calendar, and email.
        Today is \(readableDateFormatter.string(from: now)).

        Analyze the user's data below and generate a JSON array of notification items. Focus on:
        1. Tasks that are due today or overdue (type: "task_due")
        2. Upcoming calendar events happening soon (type: "event")
        3. Important unread emails that need attention (type: "important_email")
        4. Any smart reminders or suggestions (type: "reminder")

        Prioritize actionable, time-sensitive items. Be concise and helpful.
        Only include genuinely important items — don't create noise.
        If there's nothing noteworthy, return an empty array.

        ## User's Tasks
        \(tasksBlock)

        ## Today's Calendar Events
        \(eventsBlock)

        ## Recent Emails
        \(emailsBlock)

        RESPOND WITH ONLY a valid JSON array, no markdown, no explanation. Each item:
        {
          "id": "<unique string>",
          "type": "task_due" | "event" | "important_email" | "reminder",
          "title": "<short title>",
          "description": "<1-2 sentence description>",
          "priority": "high" | "medium" | "low",
          "related_id": "<task UUID or thread ID if applicable, null otherwise>"
        }
        """

        let payload = DigestChatRequest(
            messages: [
                DigestChatMessage(role: "system", content: systemPrompt),
                DigestChatMessage(role: "user", content: "Generate my notification digest.")
            ],
            model: configuration.primaryModel,
            stream: false
        )

        guard let body = try? JSONEncoder().encode(payload) else {
            errorMessage = "Failed to encode request."
            return
        }

        let baseURL = configuration.effectiveBackendURL
        let url = baseURL.appending(path: "ai/chat")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authService?.bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                errorMessage = "Server error (\(statusCode))."
                return
            }

            // The non-streaming response returns a standard OpenAI chat completion JSON
            let parsed = try parseDigestResponse(data)
            items = parsed
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Parse the AI response — expects a chat completion with JSON content.
    private func parseDigestResponse(_ data: Data) throws -> [NotificationItem] {
        // Standard OpenAI-compatible chat completion response
        struct CompletionResponse: Decodable {
            let choices: [Choice]
            struct Choice: Decodable {
                let message: Message
            }
            struct Message: Decodable {
                let content: String?
            }
        }

        let completion = try JSONDecoder().decode(CompletionResponse.self, from: data)
        guard let content = completion.choices.first?.message.content else {
            return []
        }

        // Extract JSON array from the content — the AI might wrap it in markdown code fences
        let jsonString = extractJSON(from: content)
        guard let jsonData = jsonString.data(using: .utf8) else { return [] }

        return (try? JSONDecoder().decode([NotificationItem].self, from: jsonData)) ?? []
    }

    /// Strips optional markdown code fences around JSON content.
    private func extractJSON(from content: String) -> String {
        var cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove ```json ... ``` or ``` ... ```
        if cleaned.hasPrefix("```") {
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3))
            }
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Request Models

private struct DigestChatRequest: Encodable {
    let messages: [DigestChatMessage]
    let model: String
    let stream: Bool
}

private struct DigestChatMessage: Encodable {
    let role: String
    let content: String
}
