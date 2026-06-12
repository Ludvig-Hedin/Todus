import XCTest
@testable import Todus

/// Tests target the superjson wrappers and batch-input plumbing used by
/// `TodosAPIClient`. The networking pipeline itself relies on `URLSession.shared`
/// without a protocol seam, so the 401 silent-refresh and bearer-header tests
/// are scoped to behaviours that surface through the public encoders.
@MainActor
final class TodosAPIClientTests: XCTestCase {

    // MARK: - superjson envelope

    func testSuperjsonWrapAddsDateMetaWhenPayloadContainsDate() throws {
        struct WithDate: Encodable {
            let when: Date
            let title: String
        }
        // 2026-04-27T10:26:00Z encoded as iso8601.
        let payload = WithDate(when: Date(timeIntervalSince1970: 1_777_715_160), title: "demo")

        let envelope = try TodosAPIClientTestSeam.wrapAsSuperjson(payload)

        XCTAssertNotNil(envelope["json"], "Envelope must always contain a `json` key.")
        let meta = try XCTUnwrap(envelope["meta"] as? [String: Any], "Date payloads must produce a `meta` block.")
        let values = try XCTUnwrap(meta["values"] as? [String: [String]])
        // The walker records the dotted-path of any Date-shaped string. The
        // walker uses dictionary key order, so the only contract we can pin is
        // that *the* date field is tagged.
        XCTAssertEqual(values["when"], ["Date"], "Date field must be tagged with the `Date` reviver entry.")
    }

    func testSuperjsonWrapOmitsMetaForPlainPayload() throws {
        struct PlainInput: Encodable {
            let title: String
            let count: Int
            let isReady: Bool
        }
        let payload = PlainInput(title: "hello", count: 3, isReady: true)

        let envelope = try TodosAPIClientTestSeam.wrapAsSuperjson(payload)

        XCTAssertNotNil(envelope["json"])
        XCTAssertNil(envelope["meta"], "Payloads without exotic types must not emit a meta envelope.")
    }

    func testSuperjsonWrapTagsNestedDate() throws {
        struct Outer: Encodable {
            struct Inner: Encodable {
                let createdAt: Date
            }
            let inner: Inner
        }
        let envelope = try TodosAPIClientTestSeam.wrapAsSuperjson(
            Outer(inner: .init(createdAt: Date(timeIntervalSince1970: 1_777_715_160)))
        )
        let meta = try XCTUnwrap(envelope["meta"] as? [String: Any])
        let values = try XCTUnwrap(meta["values"] as? [String: [String]])
        XCTAssertEqual(values["inner.createdAt"], ["Date"])
    }

    // MARK: - Batch input wrapping (H16 regression)

    func testBatchWrapHandlesScalarStringInputsWithoutCrashing() throws {
        // Before .fragmentsAllowed was added, JSONSerialization.data would
        // throw an uncatchable Obj-C exception on top-level strings. Just
        // running the helper without crashing is the assertion.
        let dict = try TodosAPIClientTestSeam.wrapBatchInputs(["id-1", "id-2", "id-3"])
        XCTAssertEqual(dict.count, 3)
        // Every batch entry is itself a superjson envelope.
        for i in 0..<3 {
            let entry = try XCTUnwrap(dict[String(i)] as? [String: Any])
            XCTAssertNotNil(entry["json"])
        }
    }

    func testBatchWrapHandlesScalarIntInputs() throws {
        let dict = try TodosAPIClientTestSeam.wrapBatchInputs([1, 2, 3])
        XCTAssertEqual(dict.count, 3)
        let first = try XCTUnwrap(dict["0"] as? [String: Any])
        // The wrapped value round-trips as `NSNumber` through JSONSerialization.
        XCTAssertEqual((first["json"] as? NSNumber)?.intValue, 1)
    }

    func testBatchWrapHandlesEmptyInputList() throws {
        let dict = try TodosAPIClientTestSeam.wrapBatchInputs([String]())
        XCTAssertTrue(dict.isEmpty)
    }

    // MARK: - Networking (skipped — requires URLProtocol injection refactor)

    func testBearerHeaderInjection() async throws {
        // Inject a URLProtocol stub via a custom URLSessionConfiguration so we
        // can read the Authorization header off the request that TodosAPIClient
        // would actually send. The bearer must be `Bearer <jwt>` exactly.
        APIClientURLProtocolStub.register()
        defer { APIClientURLProtocolStub.unregister() }
        let recorded = RecordedHeader()
        APIClientURLProtocolStub.responder = { request in
            recorded.value = request.value(forHTTPHeaderField: "Authorization")
            let body = Data(#"{"result":{"data":{"json":{"ok":true}}}}"#.utf8)
            let resp = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, body)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [APIClientURLProtocolStub.self] + (config.protocolClasses ?? [])

        let preload = AuthBootstrapTokens(
            bearerToken: "test.jwt.token",
            refreshToken: nil,
            currentSessionId: nil
        )
        let auth = AuthService(backendURL: URL(string: "http://stub.local")!, preloaded: preload)
        let client = TodosAPIClient(
            baseURL: URL(string: "http://stub.local")!,
            authService: auth,
            sessionConfiguration: config
        )

        struct OK: Decodable { let ok: Bool }
        let _: OK = try await client.trpcQuery("some.proc")
        XCTAssertEqual(recorded.value, "Bearer test.jwt.token",
            "Authorization header must be `Bearer <jwt>` exactly so the backend can verify the session.")
    }

    func testUnauthorizedPathTriggersRefreshAndRetryOnce() async throws {
        // First response: 401 (triggers silent refresh + retry).
        // Second response: 200 (after refresh succeeds).
        // The refresh endpoint itself also responds 200 with a fresh JWT.
        APIClientURLProtocolStub.register()
        defer { APIClientURLProtocolStub.unregister() }

        let callCount = CallCounter()
        APIClientURLProtocolStub.responder = { request in
            callCount.increment()
            let url = request.url?.absoluteString ?? ""
            if url.contains("refresh-native-token") {
                // Refresh endpoint succeeds, returning a fresh JWT.
                let body = Data(#"{"token":"refreshed.jwt.token"}"#.utf8)
                let resp = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (resp, body)
            }
            // First trpc call is 401, second (after refresh) is 200.
            let trpcCallsSoFar = callCount.trpcCalls
            if trpcCallsSoFar == 1 {
                let resp = HTTPURLResponse(
                    url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: nil
                )!
                return (resp, Data())
            }
            let body = Data(#"{"result":{"data":{"json":{"ok":true}}}}"#.utf8)
            let resp = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, body)
        }
        // Track tRPC vs refresh calls separately.
        APIClientURLProtocolStub.beforeResponse = { request in
            let url = request.url?.absoluteString ?? ""
            if !url.contains("refresh-native-token") {
                callCount.incrementTRPC()
            }
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [APIClientURLProtocolStub.self] + (config.protocolClasses ?? [])

        let preload = AuthBootstrapTokens(
            bearerToken: "stale.jwt.token",
            refreshToken: "refresh-token-valid",
            currentSessionId: nil
        )
        let auth = AuthService(backendURL: URL(string: "http://stub.local")!, preloaded: preload)
        let client = TodosAPIClient(
            baseURL: URL(string: "http://stub.local")!,
            authService: auth,
            sessionConfiguration: config
        )

        struct OK: Decodable { let ok: Bool }
        let result: OK = try await client.trpcQuery("some.proc")
        XCTAssertTrue(result.ok, "After silent refresh + retry, the request must succeed.")
        XCTAssertEqual(auth.bearerToken, "refreshed.jwt.token",
            "Bearer token must be updated to the refreshed JWT.")
    }

    // MARK: - apiDecoder date strategy (cached-formatter regression)

    func testApiDecoderParsesFractionalAndPlainISODates() throws {
        struct Payload: Decodable {
            let fractional: Date
            let plain: Date
        }
        let json = Data("""
        {"fractional":"2026-05-27T10:26:00.123Z","plain":"2026-05-27T10:26:00Z"}
        """.utf8)
        let decoded = try JSONDecoder.apiDecoder.decode(Payload.self, from: json)
        // Both should land on the same wall-clock second; fractional carries .123.
        XCTAssertEqual(
            decoded.plain.timeIntervalSince1970,
            1_779_877_560,
            accuracy: 0.001,
            "Plain ISO-8601 date must parse via the shared formatter."
        )
        XCTAssertEqual(
            decoded.fractional.timeIntervalSince1970,
            1_779_877_560.123,
            accuracy: 0.001,
            "Fractional ISO-8601 date must parse via the shared formatter."
        )
    }

    func testApiDecoderThrowsOnGarbageDate() {
        struct Payload: Decodable { let when: Date }
        let json = Data(#"{"when":"not-a-date"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder.apiDecoder.decode(Payload.self, from: json))
    }

    // MARK: - Off-main response decode (envelope + batch)

    /// The tRPC single-call decode moved into a detached task — pin that the
    /// decoded value still round-trips correctly (including Date fields, which
    /// exercise `apiDecoder` from a non-main thread).
    func testTrpcQueryDecodesEnvelopeWithDates() async throws {
        APIClientURLProtocolStub.register()
        defer { APIClientURLProtocolStub.unregister() }
        APIClientURLProtocolStub.responder = { request in
            let body = Data(#"{"result":{"data":{"json":{"id":"t1","createdAt":"2026-05-27T10:26:00Z"}}}}"#.utf8)
            let resp = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, body)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [APIClientURLProtocolStub.self] + (config.protocolClasses ?? [])
        let auth = AuthService(
            backendURL: URL(string: "http://stub.local")!,
            preloaded: AuthBootstrapTokens(bearerToken: "t", refreshToken: nil, currentSessionId: nil)
        )
        let client = TodosAPIClient(
            baseURL: URL(string: "http://stub.local")!,
            authService: auth,
            sessionConfiguration: config
        )

        struct Record: Decodable { let id: String; let createdAt: Date }
        let record: Record = try await client.trpcQuery("some.proc")
        XCTAssertEqual(record.id, "t1")
        XCTAssertEqual(record.createdAt.timeIntervalSince1970, 1_779_877_560, accuracy: 0.001)
    }

    /// Batch decode also moved off-main. Pin the per-entry Result semantics:
    /// success and error entries in the same response must map positionally.
    func testTrpcBatchQueryMapsSuccessAndErrorEntries() async throws {
        APIClientURLProtocolStub.register()
        defer { APIClientURLProtocolStub.unregister() }
        APIClientURLProtocolStub.responder = { request in
            let body = Data("""
            [
              {"result":{"data":{"json":{"ok":true}}}},
              {"error":{"json":{"message":"Thread not found"}}}
            ]
            """.utf8)
            let resp = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, body)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [APIClientURLProtocolStub.self] + (config.protocolClasses ?? [])
        let auth = AuthService(
            backendURL: URL(string: "http://stub.local")!,
            preloaded: AuthBootstrapTokens(bearerToken: "t", refreshToken: nil, currentSessionId: nil)
        )
        let client = TodosAPIClient(
            baseURL: URL(string: "http://stub.local")!,
            authService: auth,
            sessionConfiguration: config
        )

        struct OK: Decodable { let ok: Bool }
        struct In: Encodable { let id: String }
        let results: [Result<OK, Error>] = try await client.trpcBatchQuery(
            "mail.get",
            inputs: [In(id: "a"), In(id: "b")]
        )
        XCTAssertEqual(results.count, 2)
        guard case .success(let first) = results[0] else {
            return XCTFail("First entry must decode as success.")
        }
        XCTAssertTrue(first.ok)
        guard case .failure(let err) = results[1] else {
            return XCTFail("Second entry must surface as failure.")
        }
        guard case APIError.httpError(_, let bodyMessage) = err else {
            return XCTFail("Batch error entries must map to APIError.httpError.")
        }
        XCTAssertEqual(bodyMessage, "Thread not found")
    }

    /// Count mismatch between inputs and response entries must throw rather than
    /// silently mis-aligning thread ids with the wrong payloads.
    func testTrpcBatchQueryThrowsOnCountMismatch() async throws {
        APIClientURLProtocolStub.register()
        defer { APIClientURLProtocolStub.unregister() }
        APIClientURLProtocolStub.responder = { request in
            let body = Data(#"[{"result":{"data":{"json":{"ok":true}}}}]"#.utf8)
            let resp = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, body)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [APIClientURLProtocolStub.self] + (config.protocolClasses ?? [])
        let auth = AuthService(
            backendURL: URL(string: "http://stub.local")!,
            preloaded: AuthBootstrapTokens(bearerToken: "t", refreshToken: nil, currentSessionId: nil)
        )
        let client = TodosAPIClient(
            baseURL: URL(string: "http://stub.local")!,
            authService: auth,
            sessionConfiguration: config
        )

        struct OK: Decodable { let ok: Bool }
        struct In: Encodable { let id: String }
        do {
            let _: [Result<OK, Error>] = try await client.trpcBatchQuery(
                "mail.get",
                inputs: [In(id: "a"), In(id: "b")]
            )
            XCTFail("Mismatched batch count must throw.")
        } catch {
            guard case APIError.invalidResponse = error else {
                return XCTFail("Expected APIError.invalidResponse, got \(error)")
            }
        }
    }
}

// MARK: - URLProtocol stub for TodosAPIClient tests

final class RecordedHeader: @unchecked Sendable {
    var value: String?
}

final class CallCounter: @unchecked Sendable {
    private(set) var total = 0
    private(set) var trpcCalls = 0
    func increment() { total += 1 }
    func incrementTRPC() { trpcCalls += 1 }
}

final class APIClientURLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responder: ((URLRequest) -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var beforeResponse: ((URLRequest) -> Void)?

    static func register() {
        URLProtocol.registerClass(APIClientURLProtocolStub.self)
    }

    static func unregister() {
        responder = nil
        beforeResponse = nil
        URLProtocol.unregisterClass(APIClientURLProtocolStub.self)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        APIClientURLProtocolStub.beforeResponse?(request)
        guard let responder = APIClientURLProtocolStub.responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (resp, data) = responder(request)
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
