import Foundation

// MARK: - VoiceSystemPrompt

/// Server-built system instruction for a Gemini Live session. Single source
/// of truth for persona + Mem0 memories + AI profile (name/email/locale/
/// custom instructions). Mirrors the macOS implementation so voice context
/// is consistent across platforms.
struct VoiceSystemPrompt: Sendable, Decodable {
    let systemInstruction: String
    let persona: String
    let memoriesCount: Int
    let generatedAt: String
}

// MARK: - VoiceSystemPromptClient

/// Fetches the server-rendered system prompt from `GET /api/ai/voice/system-prompt`.
/// In-memory cache with a short TTL avoids hitting Mem0 on every reconnect
/// while still picking up newly-added memories within ~1 minute.
///
/// Mirrors `apps/macos/TodusMac/Services/Voice/VoiceSystemPromptClient.swift`.
@MainActor
final class VoiceSystemPromptClient {
    private let authService: AuthService
    private let backendURL: URL

    private var cached: VoiceSystemPrompt?
    private var cachedAt: Date?
    /// 60s — short enough that a memory written in another session shows up
    /// quickly when the user opens voice again, long enough that rapid
    /// reconnects (hotkey spam, brief network blips) don't hammer Mem0.
    private let ttl: TimeInterval = 60

    init(authService: AuthService, backendURL: URL) {
        self.authService = authService
        self.backendURL = backendURL
    }

    /// Returns a cached prompt if fresh, otherwise fetches from the backend.
    /// Falls back to a minimal hard-coded persona on network/auth failure so
    /// voice always has SOMETHING to send to Gemini Live's `setup` frame.
    func fetchSystemPrompt(forceRefresh: Bool = false) async -> String {
        let prompt = await fetch(forceRefresh: forceRefresh)
        return prompt.systemInstruction
    }

    /// Same as `fetchSystemPrompt` but returns the full structured prompt.
    /// Used by the `VoiceSessionCoordinator` so it can hand the
    /// `systemInstruction` directly to Gemini Live's setup frame.
    func fetch(forceRefresh: Bool = false) async -> VoiceSystemPrompt {
        if !forceRefresh, let cached, let cachedAt, Date().timeIntervalSince(cachedAt) < ttl {
            return cached
        }

        do {
            let prompt = try await performFetch()
            self.cached = prompt
            self.cachedAt = Date()
            return prompt
        } catch {
            print("[VoiceSystemPromptClient] fetch failed: \(error.localizedDescription) — using fallback prompt")
            // Stale cache is preferable to nothing — return it if we have one.
            if let cached { return cached }
            return Self.fallbackPrompt
        }
    }

    /// Force the next fetch to bypass the cache. Call when a tool that just
    /// wrote memory ran (so the user's "remember X" lands in the next session)
    /// or from the Settings "Reset voice persona cache" button.
    func invalidateCache() {
        cached = nil
        cachedAt = nil
    }

    /// Legacy alias used in some macOS-style call sites.
    func invalidate() { invalidateCache() }

    // MARK: - Private

    private func performFetch() async throws -> VoiceSystemPrompt {
        guard let token = await authService.validBearerToken() else {
            throw VoiceSystemPromptError.notAuthenticated
        }

        guard var components = URLComponents(url: backendURL, resolvingAgainstBaseURL: true) else {
            throw VoiceSystemPromptError.invalidURL
        }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = basePath + "/api/ai/voice/system-prompt"
        guard let endpoint = components.url else {
            throw VoiceSystemPromptError.invalidURL
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Voice connect already does its own retry; keep this fast so a slow
        // backend doesn't gate the WS upgrade.
        request.timeoutInterval = 5

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw VoiceSystemPromptError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw VoiceSystemPromptError.httpStatus(http.statusCode)
        }

        return try JSONDecoder().decode(VoiceSystemPrompt.self, from: data)
    }

    /// Final fallback used only when the server is unreachable AND there is no
    /// cached prompt. Keeps voice chat usable offline-ish — no memories, no
    /// profile, but the persona is intact and Gemini doesn't reject the setup.
    private static let fallbackPrompt = VoiceSystemPrompt(
        systemInstruction: """
        You are Todus, a calm, capable voice assistant.
        This is a spoken conversation — keep replies short and natural, not written prose.
        No bullet lists, no markdown, no "as an AI" filler.
        Confirm only when useful. Ask a clarifying question if the request is ambiguous.
        For destructive actions (delete, send, cancel) confirm before running the tool.
        If a tool call fails, say so plainly and offer the next step.
        """,
        persona: "Todus voice assistant",
        memoriesCount: 0,
        generatedAt: ISO8601DateFormatter().string(from: Date())
    )
}

// MARK: - Errors

enum VoiceSystemPromptError: Error, LocalizedError {
    case notAuthenticated
    case invalidURL
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not signed in"
        case .invalidURL:
            return "Invalid system-prompt URL"
        case .invalidResponse:
            return "Invalid system-prompt response"
        case .httpStatus(let code):
            return "System prompt fetch failed (HTTP \(code))"
        }
    }
}
