import Foundation

/// Unified HTTP client for all backend API calls.
/// Handles Bearer token auth, TRPC request formatting, and error handling.
@MainActor
final class TodosAPIClient {
    private let baseURL: URL
    private let authService: AuthService

    init(baseURL: URL, authService: AuthService) {
        self.baseURL = baseURL
        self.authService = authService
    }

    // MARK: - TRPC Helpers

    /// Call a TRPC query (GET-style, but uses POST for input).
    func trpcQuery<T: Decodable>(_ procedure: String, input: Encodable? = nil) async throws -> T {
        return try await trpcRequest(procedure, input: input, isMutation: false)
    }

    /// Call a TRPC mutation (POST).
    func trpcMutation<T: Decodable>(_ procedure: String, input: Encodable? = nil) async throws -> T {
        return try await trpcRequest(procedure, input: input, isMutation: true)
    }

    // MARK: - Generic HTTP

    /// Make a raw HTTP request to any backend path.
    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Encodable? = nil
    ) async throws -> T {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authService.bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if http.statusCode == 401 {
            // Try silent refresh then retry the request once with the new token
            let refreshed = await authService.attemptSilentRefresh()
            if refreshed {
                return try await retryRequest(path: path, method: method, body: body)
            }
            authService.isSessionExpired = true
            throw APIError.unauthorized
        }

        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: http.statusCode, body: String(data: data, encoding: .utf8))
        }

        return try JSONDecoder.apiDecoder.decode(T.self, from: data)
    }

    /// Retries a raw HTTP request after a successful token refresh — no further refresh attempts.
    private func retryRequest<T: Decodable>(
        path: String,
        method: String,
        body: Encodable?
    ) async throws -> T {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authService.bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        return try JSONDecoder.apiDecoder.decode(T.self, from: data)
    }

    // MARK: - Account

    /// Delete the current user's account and all associated data on the backend.
    func deleteAccount() async throws {
        let _: EmptyResponse = try await request(path: "api/auth/delete-user", method: "POST")
    }

    /// Disconnect the user's Gmail connection on the backend.
    func disconnectEmail() async throws {
        let _: EmptyResponse = try await trpcMutation("connections.delete")
    }

    // MARK: - Private

    private func trpcRequest<T: Decodable>(
        _ procedure: String,
        input: Encodable?,
        isMutation: Bool
    ) async throws -> T {
        // TRPC over HTTP: POST /api/trpc/{procedure}
        // Body: { "json": <input> } (superjson format)
        let url = baseURL.appending(path: "api/trpc/\(procedure)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authService.bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let input {
            // Wrap in superjson format: { "json": <value> }
            let inputData = try JSONEncoder().encode(input)
            let inputJSON = try JSONSerialization.jsonObject(with: inputData)
            let wrapped: [String: Any] = ["json": inputJSON]
            request.httpBody = try JSONSerialization.data(withJSONObject: wrapped)
        } else {
            request.httpBody = try JSONSerialization.data(withJSONObject: ["json": [:] as [String: Any]])
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if http.statusCode == 401 {
            // Try silent refresh then retry the TRPC request once with the new token
            let refreshed = await authService.attemptSilentRefresh()
            if refreshed {
                return try await retryTrpcRequest(procedure, input: input)
            }
            authService.isSessionExpired = true
            throw APIError.unauthorized
        }

        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: http.statusCode, body: String(data: data, encoding: .utf8))
        }

        // TRPC responses are wrapped: { "result": { "data": { "json": <value> } } }
        let trpcResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let result = trpcResponse?["result"] as? [String: Any],
           let dataObj = result["data"] as? [String: Any],
           let json = dataObj["json"] {
            let jsonData = try JSONSerialization.data(withJSONObject: json)
            return try JSONDecoder.apiDecoder.decode(T.self, from: jsonData)
        }

        // Fallback: try decoding the whole response
        return try JSONDecoder.apiDecoder.decode(T.self, from: data)
    }

    /// Retries a TRPC request after a successful token refresh — no further refresh attempts.
    private func retryTrpcRequest<T: Decodable>(
        _ procedure: String,
        input: Encodable?
    ) async throws -> T {
        let url = baseURL.appending(path: "api/trpc/\(procedure)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authService.bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let input {
            let inputData = try JSONEncoder().encode(input)
            let inputJSON = try JSONSerialization.jsonObject(with: inputData)
            let wrapped: [String: Any] = ["json": inputJSON]
            request.httpBody = try JSONSerialization.data(withJSONObject: wrapped)
        } else {
            request.httpBody = try JSONSerialization.data(withJSONObject: ["json": [:] as [String: Any]])
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        let trpcResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let result = trpcResponse?["result"] as? [String: Any],
           let dataObj = result["data"] as? [String: Any],
           let json = dataObj["json"] {
            let jsonData = try JSONSerialization.data(withJSONObject: json)
            return try JSONDecoder.apiDecoder.decode(T.self, from: jsonData)
        }
        return try JSONDecoder.apiDecoder.decode(T.self, from: data)
    }
}

/// Empty response placeholder for API calls that don't return meaningful data.
struct EmptyResponse: Decodable {}

// MARK: - API Error

enum APIError: Error, LocalizedError {
    case unauthorized
    case invalidResponse
    case httpError(statusCode: Int, body: String?)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Session expired. Please sign in again."
        case .invalidResponse: return "Invalid server response."
        case .httpError(let code, _): return "Server error (HTTP \(code))."
        case .decodingError(let error): return "Data error: \(error.localizedDescription)"
        }
    }
}

// MARK: - JSON Decoder for API responses

extension JSONDecoder {
    /// Decoder configured for API date formats (ISO 8601)
    static let apiDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            // Try ISO 8601 with fractional seconds
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }
            // Fallback without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(dateString)")
        }
        return decoder
    }()
}
