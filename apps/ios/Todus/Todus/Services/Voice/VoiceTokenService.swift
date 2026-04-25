import Foundation

// MARK: - VoiceTokenService

/// Provides the backend WebSocket proxy endpoint for live voice chat.
///
/// The Gemini API key never leaves the server — the iOS app connects to the
/// backend's `/ai/voice-ws` WebSocket proxy, which transparently relays
/// messages to Gemini. This service builds the correct WS URL and supplies
/// the Bearer token for the upgrade request.
@MainActor
final class VoiceTokenService {
    private let authService: AuthService
    private let backendURL: URL

    init(authService: AuthService, backendURL: URL) {
        self.authService = authService
        self.backendURL = backendURL
    }

    /// Returns the WebSocket proxy URL and a fresh-enough Bearer token for authentication.
    /// Voice chat uses a WebSocket handshake instead of the normal API client, so it
    /// must proactively refresh the JWT before connecting instead of waiting for a 401 retry.
    func getEndpoint() async throws -> (url: URL, token: String) {
        guard let token = await authService.validBearerToken() else {
            throw VoiceEndpointError.notAuthenticated
        }

        // Convert https → wss, http → ws for WebSocket connection
        guard var components = URLComponents(url: backendURL, resolvingAgainstBaseURL: true) else {
            throw VoiceEndpointError.invalidURL
        }
        components.scheme = (components.scheme == "https") ? "wss" : "ws"

        // Build the voice-ws proxy path — must include the /api prefix that the server mounts
        // its api router on (aiRouter is at /api/ai/..., same as the chat endpoint /api/ai/chat).
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = basePath + "/api/ai/voice-ws"

        guard let url = components.url else {
            throw VoiceEndpointError.invalidURL
        }

        return (url, token)
    }
}

// MARK: - Errors

enum VoiceEndpointError: Error, LocalizedError {
    case notAuthenticated
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not authenticated — sign in to use voice chat"
        case .invalidURL: return "Failed to build voice endpoint URL"
        }
    }
}
