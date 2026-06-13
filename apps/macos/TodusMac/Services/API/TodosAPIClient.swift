import Foundation

/// Unified HTTP client for all backend API calls.
/// Handles Bearer token auth, TRPC request formatting, retry/backoff, and error handling.
/// Adapted from the iOS TodosAPIClient for macOS.
@MainActor
final class TodosAPIClient {
    let baseURL: URL
    private let authService: AuthService
    /// Default timeout for API requests — prevents indefinite hangs on bad connectivity.
    private let requestTimeout: TimeInterval = 30
    /// Max attempts for retryable failures (5xx for queries, transient URLErrors).
    /// First attempt + up to 2 retries = 3 total. Worst-case added latency ≈ 1.3s.
    private let maxAttempts = 3

    init(baseURL: URL, authService: AuthService) {
        self.baseURL = baseURL
        self.authService = authService
    }

    private func applyClientHeaders(to request: inout URLRequest) {
        TodusHTTPClient.applyDefaultHeaders(to: &request)
    }

    // MARK: - TRPC Helpers

    /// Call a TRPC query (GET-style, but uses POST for input).
    func trpcQuery<T: Decodable>(_ procedure: String, input: Encodable? = nil) async throws -> T {
        return try await trpcSingle(procedure, input: input, isMutation: false)
    }

    /// Call a TRPC mutation (POST).
    func trpcMutation<T: Decodable>(_ procedure: String, input: Encodable? = nil) async throws -> T {
        return try await trpcSingle(procedure, input: input, isMutation: true)
    }

    /// Batched TRPC query — fans out N calls to the same procedure as a single HTTP request,
    /// using tRPC's standard `?batch=1` wire format. Returns a per-input result so partial
    /// failures don't fail the whole batch.
    func trpcBatchQuery<Input: Encodable, Output: Decodable>(
        _ procedure: String,
        inputs: [Input]
    ) async throws -> [Result<Output, Error>] {
        guard !inputs.isEmpty else { return [] }

        // tRPC v11 batch format with superjson:
        //   POST /api/trpc/proc,proc,...,proc?batch=1
        //   Body: { "0": { "json": <i0> }, "1": { "json": <i1> }, ... }
        //   Response: [ { "result": { "data": { "json": <o> } } } | { "error": { "json": { "message": "..." } } }, ... ]
        let path = "api/trpc/" + Array(repeating: procedure, count: inputs.count).joined(separator: ",")
        guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "batch", value: "1")]
        guard let url = components.url else { throw APIError.invalidResponse }

        var bodyDict: [String: Any] = [:]
        for (i, input) in inputs.enumerated() {
            let encoded = try JSONEncoder().encode(input)
            let json = try JSONSerialization.jsonObject(with: encoded)
            bodyDict[String(i)] = ["json": json]
        }
        let bodyData = try JSONSerialization.data(withJSONObject: bodyDict)

        // Capture self strongly: this client is @MainActor-bound and `self` cannot be deallocated
        // mid-request. The previous `[weak self]` fallback to a header-less URLRequest produced
        // hard-to-debug auth failures by sending requests without the Bearer/Session headers.
        let (data, _) = try await executeURLRequest(isMutation: false) { [self] in
            self.makeRequest(url: url, method: "POST", body: bodyData)
        }

        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw APIError.invalidResponse
        }
        guard array.count == inputs.count else {
            throw APIError.invalidResponse
        }

        var out: [Result<Output, Error>] = []
        out.reserveCapacity(array.count)
        for entry in array {
            if let result = entry["result"] as? [String: Any],
               let dataObj = result["data"] as? [String: Any],
               let json = dataObj["json"] {
                do {
                    // Use the null-/fragment-safe re-encoder so a single `null` or primitive
                    // result inside a batch can't crash the whole call.
                    let jsonData = try Self.serializeJSONValue(json)
                    let decoded = try JSONDecoder.apiDecoder.decode(Output.self, from: jsonData)
                    out.append(.success(decoded))
                } catch {
                    out.append(.failure(APIError.decodingError(error)))
                }
            } else if let err = entry["error"] as? [String: Any] {
                let msg = (err["json"] as? [String: Any])?["message"] as? String
                out.append(.failure(APIError.httpError(statusCode: 200, body: msg)))
            } else {
                out.append(.failure(APIError.invalidResponse))
            }
        }
        return out
    }

    // MARK: - Generic HTTP

    /// Make a raw HTTP request to any backend path.
    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Encodable? = nil
    ) async throws -> T {
        let url = baseURL.appending(path: path)
        let bodyData: Data? = try body.map { try JSONEncoder().encode($0) }
        let isMutation = method.uppercased() != "GET" && method.uppercased() != "HEAD"

        let (data, _) = try await executeURLRequest(isMutation: isMutation) { [self] in
            self.makeRequest(url: url, method: method, body: bodyData)
        }
        return try JSONDecoder.apiDecoder.decode(T.self, from: data)
    }

    // MARK: - Account

    /// Delete the current user's account and all associated data on the backend.
    func deleteAccount() async throws {
        let _: EmptyResponse = try await request(path: "api/auth/delete-user", method: "POST")
    }

    /// Disconnect the user's Gmail connection on the backend.
    /// Looks up the current connection id first because `connections.delete`
    /// requires a `connectionId` input.
    func disconnectEmail() async throws {
        struct ListResponse: Decodable {
            struct Item: Decodable { let id: String }
            let connections: [Item]
        }
        struct DeleteInput: Encodable { let connectionId: String }
        let list: ListResponse = try await trpcQuery("connections.list")
        guard let connectionId = list.connections.first?.id else { return }
        let _: EmptyResponse = try await trpcMutation(
            "connections.delete",
            input: DeleteInput(connectionId: connectionId)
        )
    }

    func listSessions() async throws -> ActiveSessionsResponse {
        try await trpcQuery("sessions.list")
    }

    func revokeSession(sessionId: String) async throws -> RevokeSessionResponse {
        try await trpcMutation("sessions.revoke", input: SessionIDInput(sessionId: sessionId))
    }

    func revokeAllSessions() async throws -> RevokeAllSessionsResponse {
        try await trpcMutation("sessions.revokeAll")
    }

    // MARK: - Private

    private func trpcSingle<T: Decodable>(
        _ procedure: String,
        input: Encodable?,
        isMutation: Bool
    ) async throws -> T {
        // TRPC over HTTP: POST /api/trpc/{procedure}, body { "json": <input> } (superjson).
        let url = baseURL.appending(path: "api/trpc/\(procedure)")
        let bodyData: Data
        if let input {
            let encoded = try JSONEncoder().encode(input)
            let json = try JSONSerialization.jsonObject(with: encoded)
            bodyData = try JSONSerialization.data(withJSONObject: ["json": json])
        } else {
            bodyData = try JSONSerialization.data(withJSONObject: ["json": [:] as [String: Any]])
        }

        let (data, _) = try await executeURLRequest(isMutation: isMutation) { [self] in
            self.makeRequest(url: url, method: "POST", body: bodyData)
        }

        // TRPC responses are wrapped: { "result": { "data": { "json": <value> } } }
        if let trpcResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let result = trpcResponse["result"] as? [String: Any],
           let dataObj = result["data"] as? [String: Any],
           let json = dataObj["json"] {
            let jsonData = try Self.serializeJSONValue(json)
            return try JSONDecoder.apiDecoder.decode(T.self, from: jsonData)
        }

        // Fallback: try decoding the whole response (e.g. for endpoints not wrapped in tRPC envelope)
        return try JSONDecoder.apiDecoder.decode(T.self, from: data)
    }

    /// Re-encodes a value extracted from `dataObj["json"]` back to `Data`.
    ///
    /// `JSONSerialization.data(withJSONObject:)` throws an *uncatchable* Objective-C
    /// `NSInvalidArgumentException` when given `NSNull` or any primitive (string/number/bool)
    /// at the top level — this is what crashed the app for void-returning mutations like
    /// `mail.forceSync` whose tRPC payload is `{ json: null }`. Special-case null to a `{}`
    /// stand-in so empty `Decodable` structs decode cleanly, and use `.fragmentsAllowed`
    /// for the rest so primitive returns (e.g. a bare string id) round-trip safely.
    private static func serializeJSONValue(_ value: Any) throws -> Data {
        if value is NSNull {
            return try JSONSerialization.data(withJSONObject: [:] as [String: Any])
        }
        return try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
    }

    /// Builds a URLRequest with current bearer token + session id. Called per-attempt so we
    /// always pick up the latest token (e.g. after a silent refresh between attempts).
    private func makeRequest(url: URL, method: String, body: Data?) -> URLRequest {
        var req = URLRequest(url: url, timeoutInterval: requestTimeout)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyClientHeaders(to: &req)
        if let token = authService.bearerToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let sessionId = authService.currentSessionId {
            req.setValue(sessionId, forHTTPHeaderField: "X-Todus-Session-Id")
        }
        req.httpBody = body
        return req
    }

    /// Drives request lifecycle: send → 401 silent-refresh-and-retry once → backoff retry on 5xx
    /// (queries only) and transient URLErrors.
    private func executeURLRequest(
        isMutation: Bool,
        build: () -> URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        var didRefresh = false

        while true {
            // Stop promptly if the surrounding task was cancelled (folder switch,
            // view torn down, or a `withTimeout` deadline). Without this the loop
            // could burn another attempt — and a full URLSession timeout — on work
            // whose result will be discarded.
            try Task.checkCancellation()
            attempt += 1
            let req = build()

            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                guard let http = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }
                authService.captureRotatedToken(from: http)

                if http.statusCode == 401 {
                    if !didRefresh {
                        didRefresh = true
                        let refreshed = await authService.attemptSilentRefresh()
                        if refreshed { continue }
                    }
                    authService.isSessionExpired = true
                    throw APIError.unauthorized
                }

                if (500..<600).contains(http.statusCode) {
                    if !isMutation, attempt < maxAttempts {
                        await sleepBackoff(attempt: attempt)
                        continue
                    }
                    throw APIError.httpError(statusCode: http.statusCode, body: String(data: data, encoding: .utf8))
                }

                guard (200..<300).contains(http.statusCode) else {
                    throw APIError.httpError(statusCode: http.statusCode, body: String(data: data, encoding: .utf8))
                }

                return (data, http)
            } catch let urlError as URLError {
                let retryable: Bool = {
                    if attempt >= maxAttempts { return false }
                    if isMutation {
                        switch urlError.code {
                        case .notConnectedToInternet, .cannotFindHost,
                             .cannotConnectToHost, .dnsLookupFailed:
                            return true
                        default:
                            return false
                        }
                    } else {
                        switch urlError.code {
                        case .notConnectedToInternet, .networkConnectionLost,
                             .cannotFindHost, .cannotConnectToHost,
                             .dnsLookupFailed, .timedOut:
                            return true
                        default:
                            return false
                        }
                    }
                }()
                if retryable {
                    await sleepBackoff(attempt: attempt)
                    continue
                }
                throw urlError
            }
        }
    }

    private func sleepBackoff(attempt: Int) async {
        let baseMillis: UInt64
        switch attempt {
        case 1: baseMillis = 100
        case 2: baseMillis = 300
        default: baseMillis = 900
        }
        let jitter = UInt64.random(in: 0...80)
        try? await Task.sleep(nanoseconds: (baseMillis + jitter) * 1_000_000)
    }
}

/// Empty response placeholder for API calls that don't return meaningful data.
struct EmptyResponse: Decodable {}

struct ActiveSessionRecord: Decodable, Identifiable {
    let id: String
    let device: String
    let location: String
    let createdAt: Date
    let updatedAt: Date
    let isCurrent: Bool?

    /// SF Symbol name appropriate for the session's device type based on the device label.
    var deviceIcon: String {
        let d = device.lowercased()
        if d.contains("ipad") { return "ipad" }
        if d.contains("iphone") || d.contains("ios") { return "iphone" }
        if d.contains("mac") { return "desktopcomputer" }
        if d.contains("android") { return "phone" }
        return "laptopcomputer"
    }
}

struct ActiveSessionsResponse: Decodable {
    let sessions: [ActiveSessionRecord]
}

private struct SessionIDInput: Encodable {
    let sessionId: String
}

struct RevokeSessionResponse: Decodable {
    let success: Bool
    let revokedCurrent: Bool
}

struct RevokeAllSessionsResponse: Decodable {
    let success: Bool
    let revokedCount: Int
    let revokedCurrent: Bool
}

// MARK: - API Error

/// Pulls tRPC / JSON-RPC `message` from error bodies like `{ "error": { "json": { "message": "..." } } }`.
private func trpcErrorMessageFromBody(_ body: String?) -> String? {
    guard let body, let data = body.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let err = obj["error"] as? [String: Any]
    else { return nil }
    if let json = err["json"] as? [String: Any],
       let msg = json["message"] as? String,
       !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return msg
    }
    return nil
}

enum APIError: Error, LocalizedError {
    case unauthorized
    case invalidResponse
    case httpError(statusCode: Int, body: String?)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Your session has expired. Please sign in again."
        case .invalidResponse: return "Invalid server response."
        case .httpError(let code, let body):
            if let trpc = trpcErrorMessageFromBody(body) { return trpc }
            return "Server error (HTTP \(code))."
        case .decodingError(let error): return "Data error: \(error.localizedDescription)"
        }
    }
}

extension Error {
    /// True when the error represents a normal task cancellation (e.g. SwiftUI dismissing
    /// a view and tearing down its `.task`). These should be filtered from error logs.
    var isURLCancellation: Bool {
        if let urlError = self as? URLError, urlError.code == .cancelled { return true }
        if self is CancellationError { return true }
        return false
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
