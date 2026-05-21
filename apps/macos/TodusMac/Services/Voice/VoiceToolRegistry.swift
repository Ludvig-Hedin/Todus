import Foundation
import SwiftData

// MARK: - VoiceToolExecutor

/// Pi-portable boundary. The macOS app implements this with `MacVoiceToolExecutor`
/// (which dispatches into `MacAIChatService`). A future Raspberry Pi voice
/// daemon (Python) will provide its own implementation that hits the same
/// tRPC endpoints over HTTP — the tool *declarations* live below and are
/// platform-neutral; only the dispatch layer differs per host.
///
/// Returning a JSON string keeps the contract identical to Gemini Live's
/// expected `toolResponse.functionResponses[].response.result` shape.
@MainActor
protocol VoiceToolExecutor: AnyObject {
    /// Execute a tool call by name. Implementations must always return a
    /// JSON string — never throw — so Gemini Live doesn't hang waiting for
    /// a response. Failures should be encoded as `{"success":false,"message":...}`.
    func executeVoiceTool(name: String, argumentsJSON: String) async -> String
}

// MARK: - VoiceToolRegistry

/// Phase-1 voice tool surface. Three task tools delegate to the macOS chat
/// service (already wired through tRPC), one local-only `get_time` tool
/// answers without a round-trip.
///
/// Tool list intentionally short: every tool call adds a turn to the Gemini
/// Live session, and Gemini's tool-routing latency is sensitive to the
/// number of declarations. Add more tools only when the user asks for them.
enum VoiceToolRegistry {

    /// Gemini Live `setup.tools[0].functionDeclarations` payload.
    /// Schema follows the OpenAPI subset Gemini accepts (string / object /
    /// enum). Keep parameter names and enum values byte-identical to the
    /// existing text-chat tool definitions so a future merger is trivial.
    static var declarations: [[String: Any]] {
        [
            [
                "name": "create_task",
                "description": "Create a new task in the user's task list. Use when the user says 'remind me to', 'add a task', 'I need to', etc.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "title": [
                            "type": "string",
                            "description": "Short title for the task (1 sentence)."
                        ],
                        "dueDate": [
                            "type": "string",
                            "description": "Optional ISO 8601 due date/time. Resolve relative phrases ('tomorrow', 'next Friday at 3pm') from the locale block in the system prompt."
                        ],
                        "priority": [
                            "type": "string",
                            "description": "Optional priority.",
                            "enum": ["none", "low", "medium", "high"]
                        ]
                    ],
                    "required": ["title"]
                ]
            ],
            [
                "name": "update_task",
                "description": "Update an existing task by its UUID.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "Task UUID."],
                        "title": ["type": "string"],
                        "status": [
                            "type": "string",
                            "enum": ["todo", "doing", "done"]
                        ],
                        "priority": [
                            "type": "string",
                            "enum": ["none", "low", "medium", "high"]
                        ],
                        "dueDate": ["type": "string", "description": "ISO 8601, or empty string to clear."]
                    ],
                    "required": ["id"]
                ]
            ],
            [
                "name": "delete_task",
                "description": "Delete a task by its UUID. Confirm out loud with the user before calling.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "Task UUID."]
                    ],
                    "required": ["id"]
                ]
            ],
            [
                "name": "get_time",
                "description": "Return the user's current local date and time. Use only when the user explicitly asks. The system prompt already includes the local time at session start.",
                "parameters": [
                    "type": "object",
                    "properties": [:]
                ]
            ]
        ]
    }

    /// Dispatch a tool call. `get_time` is handled inline (zero-latency local
    /// answer); everything else routes through the executor (Mac → SwiftData
    /// + tRPC; Pi → tRPC over HTTP).
    @MainActor
    static func execute(
        name: String,
        argumentsJSON: String,
        executor: VoiceToolExecutor
    ) async -> String {
        switch name {
        case "get_time":
            return getTimeResult()
        default:
            return await executor.executeVoiceTool(name: name, argumentsJSON: argumentsJSON)
        }
    }

    // MARK: - Local tool: get_time

    private static func getTimeResult() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        let now = formatter.string(from: Date())

        let iso = ISO8601DateFormatter().string(from: Date())

        struct Result: Encodable {
            let success: Bool
            let localTime: String
            let isoTime: String
            let timezone: String
        }
        let result = Result(
            success: true,
            localTime: now,
            isoTime: iso,
            timezone: TimeZone.current.identifier
        )
        if let data = try? JSONEncoder().encode(result),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{\"success\":true,\"localTime\":\"\(now)\"}"
    }
}

// MARK: - MacVoiceToolExecutor

/// macOS executor: turns a Gemini tool call into a SwiftData mutation via
/// `MacAIChatService.executeVoiceTool`. Lives here (not on the chat service)
/// so the Pi-portable boundary is a single Swift file.
@MainActor
final class MacVoiceToolExecutor: VoiceToolExecutor {
    private let chatService: MacAIChatService
    private let modelContext: ModelContext

    init(chatService: MacAIChatService, modelContext: ModelContext) {
        self.chatService = chatService
        self.modelContext = modelContext
    }

    func executeVoiceTool(name: String, argumentsJSON: String) async -> String {
        await chatService.executeVoiceTool(
            name: name,
            argumentsJSON: argumentsJSON,
            modelContext: modelContext
        )
    }
}
