import Foundation

/// Unified HTTP client for all backend API calls.
/// Handles Bearer token auth, TRPC request formatting, retry/backoff, and error handling.
@MainActor
final class TodosAPIClient {
    private let baseURL: URL
    private let authService: AuthService
    /// Default timeout for API requests — prevents indefinite hangs on bad connectivity.
    private let requestTimeout: TimeInterval = 30
    /// Max attempts for retryable failures (5xx for queries, transient URLErrors).
    /// First attempt + up to 2 retries = 3 total. Worst-case added latency ≈ 1.3s.
    private let maxAttempts = 3
    /// Networking session — defaults to `URLSession.shared`. Tests inject a
    /// `URLSession` configured with a `URLProtocol` stub so 401 silent-refresh
    /// retry and bearer-header behaviour can be asserted without hitting the wire.
    private let session: URLSession

    init(baseURL: URL, authService: AuthService) {
        self.baseURL = baseURL
        self.authService = authService
        self.session = URLSession.shared
    }

    /// Internal init that accepts a custom `URLSessionConfiguration`. Used by
    /// unit tests to register a `URLProtocol` stub for the underlying session
    /// without breaking the public `init(baseURL:authService:)` contract.
    init(baseURL: URL, authService: AuthService, sessionConfiguration: URLSessionConfiguration) {
        self.baseURL = baseURL
        self.authService = authService
        self.session = URLSession(configuration: sessionConfiguration)
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
    ///
    /// Used to collapse the inbox cold-start enrichment from N round trips into 1.
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
            // Use the iso8601-only encoder so dates round-trip consistently with the
            // superjson-aware wrap below. Allow fragments at the per-input layer so a
            // scalar (e.g. String/Int) input doesn't trip `JSONSerialization`'s
            // top-level-collection requirement.
            let encoded = try Self.superjsonEncoder.encode(input)
            let json = try JSONSerialization.jsonObject(with: encoded, options: [.fragmentsAllowed])
            bodyDict[String(i)] = Self.superjsonWrap(json)
        }
        // `.fragmentsAllowed` guards against pathological cases where `bodyDict` is
        // empty or a future call passes a non-dictionary root — historically this
        // raised an uncatchable Obj-C exception (see [H16]).
        let bodyData = try JSONSerialization.data(withJSONObject: bodyDict, options: [.fragmentsAllowed])

        let (data, _) = try await executeURLRequest(isMutation: false) {
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

        let (data, _) = try await executeURLRequest(isMutation: isMutation) {
            self.makeRequest(url: url, method: method, body: bodyData)
        }
        return try JSONDecoder.apiDecoder.decode(T.self, from: data)
    }

    /// Send a pre-encoded request body to any backend path and return the raw response
    /// `Data`. Reuses the same auth header + silent-refresh + backoff pipeline as the
    /// other helpers so non-tRPC endpoints (e.g. `/api/ai/chat`) don't have to hand-roll
    /// their own URLSession plumbing.
    func sendRawData(
        path: String,
        method: String = "POST",
        body: Data?,
        extraHeaders: [String: String] = [:]
    ) async throws -> Data {
        let url = baseURL.appending(path: path)
        let isMutation = method.uppercased() != "GET" && method.uppercased() != "HEAD"

        let (data, _) = try await executeURLRequest(isMutation: isMutation) {
            var req = self.makeRequest(url: url, method: method, body: body)
            for (key, value) in extraHeaders {
                req.setValue(value, forHTTPHeaderField: key)
            }
            return req
        }
        return data
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
        // TRPC over HTTP: POST /api/trpc/{procedure}, body { "json": <input>, "meta": {...}? }
        // wrapped to match the superjson wire format the server expects. Dates serialize as
        // ISO-8601 strings with a `meta.values["…"] = ["Date"]` reviver entry; Sets become
        // arrays with a matching `Set` reviver. See [H15].
        let url = baseURL.appending(path: "api/trpc/\(procedure)")
        let bodyData: Data
        if let input {
            let encoded = try Self.superjsonEncoder.encode(input)
            // `.fragmentsAllowed` so scalar inputs (a bare String/Int) don't trip
            // JSONSerialization's collection-root requirement.
            let json = try JSONSerialization.jsonObject(with: encoded, options: [.fragmentsAllowed])
            bodyData = try JSONSerialization.data(
                withJSONObject: Self.superjsonWrap(json),
                options: [.fragmentsAllowed]
            )
        } else {
            bodyData = try JSONSerialization.data(withJSONObject: ["json": [:] as [String: Any]])
        }

        let (data, _) = try await executeURLRequest(isMutation: isMutation) {
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
    /// at the top level — this crashes the app for void-returning mutations like
    /// `mail.forceSync` whose tRPC payload is `{ json: null }`. Special-case null to a `{}`
    /// stand-in so empty `Decodable` structs decode cleanly, and use `.fragmentsAllowed`
    /// for the rest so primitive returns (e.g. a bare string id) round-trip safely.
    private static func serializeJSONValue(_ value: Any) throws -> Data {
        if value is NSNull {
            return try JSONSerialization.data(withJSONObject: [:] as [String: Any])
        }
        return try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
    }

    // MARK: - Superjson wire format

    /// Dedicated encoder used for tRPC bodies. Forces ISO-8601 dates so the
    /// `Date` reviver added by `superjsonWrap` matches what the server parses.
    /// We don't share `JSONDecoder.apiDecoder`'s symmetric encoder because some
    /// non-tRPC paths still use the default `JSONEncoder` defaults.
    private static let superjsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// Wraps a JSON-serialised value in tRPC's superjson envelope. Walks the tree
    /// once to collect reviver entries for non-JSON-native values that the server
    /// expects (Date, Set, undefined). Returns `{ "json": ... }` if nothing exotic
    /// was found, or `{ "json": ..., "meta": { "values": { "<keypath>": ["Date"] } } }`
    /// otherwise.
    ///
    /// NOTE: Swift's `JSONSerialization` does not preserve `Set` (it surfaces as an
    /// `Array`) nor `Date` (already coerced to an ISO-8601 string by
    /// `superjsonEncoder`). We detect Dates by inspecting string values against an
    /// ISO-8601 shape — false positives are harmless because the server's reviver
    /// just re-parses the same string. `BigInt` is not represented in Swift's JSON
    /// pipeline so we intentionally skip it.
    private static func superjsonWrap(_ json: Any) -> [String: Any] {
        var meta: [String: [String]] = [:]
        collectSuperjsonMeta(value: json, path: "", into: &meta)
        if meta.isEmpty {
            return ["json": json]
        }
        return [
            "json": json,
            "meta": ["values": meta as Any],
        ]
    }

    /// Walks a JSON value tree and records the dotted-path of every Date-shaped string.
    /// Path syntax matches superjson's: `"a.b.0.c"` (dictionary keys + array indices).
    /// Empty path indicates the root value itself is a Date.
    private static func collectSuperjsonMeta(value: Any, path: String, into meta: inout [String: [String]]) {
        if let str = value as? String, looksLikeISO8601Date(str) {
            meta[path.isEmpty ? "" : path] = ["Date"]
            return
        }
        if let dict = value as? [String: Any] {
            for (key, child) in dict {
                let childPath = path.isEmpty ? key : "\(path).\(key)"
                collectSuperjsonMeta(value: child, path: childPath, into: &meta)
            }
            return
        }
        if let array = value as? [Any] {
            for (index, child) in array.enumerated() {
                let childPath = path.isEmpty ? "\(index)" : "\(path).\(index)"
                collectSuperjsonMeta(value: child, path: childPath, into: &meta)
            }
            return
        }
    }

    /// Cheap ISO-8601 shape check — avoids spinning up `ISO8601DateFormatter` for
    /// every string in the request body. Matches `YYYY-MM-DDTHH:MM:SS` with an
    /// optional fractional second and timezone designator.
    private static func looksLikeISO8601Date(_ s: String) -> Bool {
        // Length 20–35 covers `2025-04-27T10:26:00Z` … `2025-04-27T10:26:00.123456+00:00`.
        guard s.count >= 20, s.count <= 35 else { return false }
        guard let t = s.firstIndex(of: "T") else { return false }
        let datePart = s[s.startIndex..<t]
        // YYYY-MM-DD: positions 4 and 7 must be "-".
        guard datePart.count == 10 else { return false }
        let chars = Array(datePart)
        guard chars[4] == "-", chars[7] == "-" else { return false }
        // Time must start with HH:MM:SS.
        let afterT = s.index(after: t)
        guard s.distance(from: afterT, to: s.endIndex) >= 8 else { return false }
        let timeHead = s[afterT..<s.index(afterT, offsetBy: 8)]
        let timeChars = Array(timeHead)
        return timeChars[2] == ":" && timeChars[5] == ":"
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
    /// (queries only) and transient URLErrors. The build closure is re-invoked per attempt so a
    /// rotated bearer token is always picked up.
    private func executeURLRequest(
        isMutation: Bool,
        build: () -> URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        var didRefresh = false

        while true {
            attempt += 1
            let req = build()

            do {
                let (data, response) = try await session.data(for: req)
                guard let http = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }
                authService.captureRotatedToken(from: http)

                if http.statusCode == 401 {
                    if !didRefresh {
                        didRefresh = true
                        let refreshed = await authService.attemptSilentRefresh()
                        if refreshed { continue } // retry with the refreshed token on the next attempt
                    }
                    // A seeded UI-testing session legitimately 401s against the real
                    // backend; don't raise the global "Session expired" banner for it.
                    if !authService.isUITestingSession {
                        authService.isSessionExpired = true
                    }
                    throw APIError.unauthorized
                }

                if (500..<600).contains(http.statusCode) {
                    // Retry queries on 5xx; mutations are not retried automatically because they
                    // may have already been processed server-side before the failure surfaced.
                    if !isMutation, attempt < maxAttempts {
                        try await sleepBackoff(attempt: attempt)
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
                        // Only retry mutations on errors that clearly mean the request didn't reach
                        // the server — anything mid-flight could have been processed.
                        switch urlError.code {
                        case .notConnectedToInternet, .cannotFindHost,
                             .cannotConnectToHost, .dnsLookupFailed:
                            return true
                        default:
                            return false
                        }
                    } else {
                        // Queries are idempotent; retry on most network errors.
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
                    try await sleepBackoff(attempt: attempt)
                    continue
                }
                throw urlError
            }
        }
    }

    /// Exponential backoff with jitter: ~100ms, ~300ms, ~900ms.
    /// Throws `CancellationError` if the parent task is cancelled mid-wait so the
    /// retry loop exits promptly instead of running another attempt.
    private func sleepBackoff(attempt: Int) async throws {
        let baseMillis: UInt64
        switch attempt {
        case 1: baseMillis = 100
        case 2: baseMillis = 300
        default: baseMillis = 900
        }
        let jitter = UInt64.random(in: 0...80)
        try await Task.sleep(nanoseconds: (baseMillis + jitter) * 1_000_000)
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

enum APIError: Error, LocalizedError {
    case unauthorized
    case invalidResponse
    case httpError(statusCode: Int, body: String?)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Your session has expired. Please sign in again."
        case .invalidResponse: return "Invalid server response."
        case .httpError(let code, _): return "Server error (HTTP \(code))."
        case .decodingError(let error): return "Data error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Test seams (additive, non-breaking)

/// Surfaces the private superjson wrappers to unit tests without changing the
/// public API or relaxing access on the production call sites. The helpers
/// delegate to the same code paths used by `trpcMutation` / `trpcBatchQuery`.
enum TodosAPIClientTestSeam {
    /// Re-encodes `value` through the same pipeline `trpcSingle` uses (superjson
    /// envelope + `JSONSerialization`) and returns the resulting JSON object so
    /// tests can assert envelope shape, `meta.values`, etc.
    @MainActor
    static func wrapAsSuperjson<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(value)
        let json = try JSONSerialization.jsonObject(with: encoded, options: [.fragmentsAllowed])
        return TodosAPIClient.superjsonWrap_forTesting(json)
    }

    /// Exposes the batch-wrap pipeline for a heterogenous list of scalar /
    /// object inputs without crashing on top-level fragments (H16).
    @MainActor
    static func wrapBatchInputs<T: Encodable>(_ inputs: [T]) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var bodyDict: [String: Any] = [:]
        for (i, input) in inputs.enumerated() {
            let encoded = try encoder.encode(input)
            let json = try JSONSerialization.jsonObject(with: encoded, options: [.fragmentsAllowed])
            bodyDict[String(i)] = TodosAPIClient.superjsonWrap_forTesting(json)
        }
        // Round-trip through JSONSerialization to mirror the production call;
        // this is what historically tripped `NSInvalidArgumentException` on
        // scalar inputs before `.fragmentsAllowed` was added.
        _ = try JSONSerialization.data(withJSONObject: bodyDict, options: [.fragmentsAllowed])
        return bodyDict
    }
}

extension TodosAPIClient {
    /// Internal accessor used only by `TodosAPIClientTestSeam`. Wraps the
    /// existing private `superjsonWrap` so tests don't poke at the production
    /// implementation directly.
    static func superjsonWrap_forTesting(_ json: Any) -> [String: Any] {
        return superjsonWrap(json)
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
