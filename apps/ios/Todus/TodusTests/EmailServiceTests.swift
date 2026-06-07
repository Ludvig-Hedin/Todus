import XCTest
@testable import Todus

/// EmailService is `@MainActor` and accepts a concrete `TodosAPIClient` (no
/// protocol seam). Driving the mutation paths from a unit test requires
/// either:
///   (1) a `MailAPIRequesting` protocol on TodosAPIClient that EmailService
///       can accept in init, or
///   (2) a URLProtocol stub injected through a custom URLSessionConfiguration
///       that TodosAPIClient is told to use.
/// Both refactors are additive but exceed the scope of this test pass. The
/// type-level contracts (e.g. `archiveThreads` returns `Bool`) are pinned
/// here so a regression that changes the return type fails to compile.
@MainActor
final class EmailServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeStubbedService(
        responder: @escaping (URLRequest) -> (HTTPURLResponse, Data)
    ) -> EmailService {
        EmailServiceURLProtocolStub.register()
        EmailServiceURLProtocolStub.responder = responder
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [EmailServiceURLProtocolStub.self] + (config.protocolClasses ?? [])
        let auth = AuthService(
            backendURL: URL(string: "http://stub.local")!,
            preloaded: AuthBootstrapTokens(bearerToken: "t", refreshToken: nil, currentSessionId: nil)
        )
        let api = TodosAPIClient(
            baseURL: URL(string: "http://stub.local")!,
            authService: auth,
            sessionConfiguration: config
        )
        return EmailService(api: api)
    }

    // MARK: - Return-type contracts (H3-H5 fixes)

    func testMutationReturnTypesAreBool() async throws {
        // Returns Bool on success — stub returns 200 with an empty trpc result.
        let svc = makeStubbedService { request in
            let body = Data(#"{"result":{"data":{"json":{}}}}"#.utf8)
            let resp = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, body)
        }
        defer { EmailServiceURLProtocolStub.unregister() }

        let r1: Bool = await svc.archiveThreads(ids: ["t1"])
        let r2: Bool = await svc.markAsRead(ids: ["t1"])
        let r3: Bool = await svc.markAsRead(ids: ["t1"], silent: true)
        let r4: Bool = await svc.markAsUnread(ids: ["t1"])
        let r5: Bool = await svc.markAsSpam(ids: ["t1"])
        let r6: Bool = await svc.toggleStar(ids: ["t1"])
        let r7: Bool = await svc.deleteThreads(ids: ["t1"])

        XCTAssertTrue(r1 && r2 && r3 && r4 && r5 && r6 && r7,
            "All mutation methods must keep their Bool return type and return true on a successful stub response.")
    }

    // MARK: - Pagination dedupe

    func testPaginationDedupePreservesNewerVersion() {
        // Existing page: thread t1 with old unread=true, t2 unread=false.
        let baseDate = Date(timeIntervalSince1970: 1_000_000_000)
        let sender = EmailSender(name: "A", email: "a@x")
        let t1Old = EmailThread(
            id: "t1", subject: "s", snippet: "old",
            from: sender, date: baseDate, unread: true, messageCount: 1, labels: ["INBOX"]
        )
        let t2 = EmailThread(
            id: "t2", subject: "s", snippet: "n",
            from: sender, date: baseDate, unread: false, messageCount: 1, labels: ["INBOX"]
        )

        // Incoming page: t1 with NEW unread=false (flipped), new t3.
        let t1New = EmailThread(
            id: "t1", subject: "s", snippet: "old",
            from: sender, date: baseDate, unread: false, messageCount: 1, labels: ["INBOX"]
        )
        let t3 = EmailThread(
            id: "t3", subject: "s", snippet: "n",
            from: sender, date: baseDate, unread: true, messageCount: 1, labels: ["INBOX"]
        )

        let merged = EmailService.mergePages(existing: [t1Old, t2], incoming: [t1New, t3])

        XCTAssertEqual(merged.count, 3, "Merge must dedupe t1 and append t3.")
        XCTAssertEqual(merged[0].id, "t1")
        XCTAssertFalse(merged[0].unread, "Newer t1 (unread=false) must replace older t1 (unread=true).")
        XCTAssertEqual(merged[1].id, "t2")
        XCTAssertEqual(merged[2].id, "t3", "New ids must be appended at the end.")
    }

    func testPaginationDedupeKeepsExistingWhenIncomingIsNotNewer() {
        let baseDate = Date(timeIntervalSince1970: 1_000_000_000)
        let sender = EmailSender(name: "A", email: "a@x")
        let t1 = EmailThread(
            id: "t1", subject: "s", snippet: "x",
            from: sender, date: baseDate, unread: true, messageCount: 1, labels: ["INBOX"]
        )
        let t1Dup = EmailThread(
            id: "t1", subject: "s", snippet: "x",
            from: sender, date: baseDate, unread: true, messageCount: 1, labels: ["INBOX"]
        )
        let merged = EmailService.mergePages(existing: [t1], incoming: [t1Dup])
        XCTAssertEqual(merged.count, 1, "Identical incoming row must be dropped, not appended.")
    }

    // MARK: - Silent read suppresses errorMessage

    func testMarkAsReadSilentDoesNotMutateErrorMessage() async {
        // Stub returns 500 on every call → mutation fails.
        let svc = makeStubbedService { request in
            let resp = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            return (resp, Data())
        }
        defer { EmailServiceURLProtocolStub.unregister() }

        // First mutation: silent=true must NOT set errorMessage.
        svc.errorMessage = nil
        let r1 = await svc.markAsRead(ids: ["t1"], silent: true)
        XCTAssertFalse(r1)
        XCTAssertNil(svc.errorMessage,
            "silent=true must suppress the user-facing errorMessage so background reads don't flash a banner.")

        // Second mutation: silent=false must set errorMessage on the same failure.
        let r2 = await svc.markAsRead(ids: ["t1"], silent: false)
        XCTAssertFalse(r2)
        XCTAssertNotNil(svc.errorMessage,
            "silent=false must populate errorMessage for user-initiated mark-as-read.")
    }

    // MARK: - restoreThreadSnapshots (rollback contract)

    func testThreadSnapshotsCanRoundTripThroughEquatable() {
        // `restoreThreadSnapshots` is private but its correctness depends on
        // EmailThread satisfying `Equatable` and `Identifiable`. Pin those
        // here so a future refactor that drops Equatable (or removes the `id`
        // field) shows up as a compilation failure.
        let sender = EmailSender(name: "Alice", email: "alice@example.com")
        let thread = EmailThread(
            id: "t-1",
            subject: "Hello",
            snippet: "world",
            from: sender,
            date: Date(timeIntervalSince1970: 1_000_000_000),
            unread: true,
            messageCount: 1,
            labels: ["INBOX"]
        )
        let copy = thread
        XCTAssertEqual(thread, copy)
        XCTAssertEqual(thread.id, "t-1")
    }

    // MARK: - toggleStar optimistic update + rollback (IOS-0608-3)

    private func seededThread(labels: [String]) -> EmailThread {
        EmailThread(
            id: "t1", subject: "s", snippet: "x",
            from: EmailSender(name: "A", email: "a@x.com"),
            date: Date(timeIntervalSince1970: 1_000_000_000),
            unread: false, messageCount: 1, labels: labels
        )
    }

    private func okResponder(_ request: URLRequest) -> (HTTPURLResponse, Data) {
        let body = Data(#"{"result":{"data":{"json":{}}}}"#.utf8)
        let resp = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (resp, body)
    }

    func testToggleStarAddsStarLocallyOnSuccess() async {
        let svc = makeStubbedService { self.okResponder($0) }
        defer { EmailServiceURLProtocolStub.unregister() }
        svc.threads = [seededThread(labels: ["INBOX"])]

        let ok = await svc.toggleStar(ids: ["t1"])

        XCTAssertTrue(ok)
        XCTAssertTrue(svc.threads[0].labels.contains("STARRED"),
            "A successful toggle must reflect the STARRED label locally so the row updates without a reload.")
    }

    func testToggleStarRemovesStarWhenAlreadyStarred() async {
        let svc = makeStubbedService { self.okResponder($0) }
        defer { EmailServiceURLProtocolStub.unregister() }
        svc.threads = [seededThread(labels: ["INBOX", "STARRED"])]

        let ok = await svc.toggleStar(ids: ["t1"])

        XCTAssertTrue(ok)
        XCTAssertFalse(svc.threads[0].labels.contains("STARRED"),
            "Toggling an already-starred thread must remove STARRED.")
    }

    func testToggleStarRollsBackOptimisticUpdateOnFailure() async {
        // Stub fails every request with 500 → server reject.
        let svc = makeStubbedService { request in
            let resp = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            return (resp, Data())
        }
        defer { EmailServiceURLProtocolStub.unregister() }
        svc.threads = [seededThread(labels: ["INBOX"])]

        let ok = await svc.toggleStar(ids: ["t1"])

        XCTAssertFalse(ok)
        XCTAssertEqual(svc.threads[0].labels, ["INBOX"],
            "A failed toggle must roll back to the exact original labels — not leave a phantom star.")
    }

    // MARK: - EmailMessage date parsing (cached formatters — IOS perf)

    private func decodeMessage(receivedOn: String) throws -> EmailMessage {
        let json = Data(#"{"id":"m1","sender":{"name":"A","email":"a@x.com"},"receivedOn":"\#(receivedOn)"}"#.utf8)
        return try JSONDecoder().decode(EmailMessage.self, from: json)
    }

    private func utcComponents(_ date: Date) -> DateComponents {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    func testParsesISO8601WithFractionalSeconds() throws {
        let msg = try decodeMessage(receivedOn: "2025-03-24T10:30:00.500Z")
        XCTAssertNotEqual(msg.date, .distantPast, "ISO-8601 fractional-seconds date must parse.")
        let c = utcComponents(msg.date)
        XCTAssertEqual(c.year, 2025); XCTAssertEqual(c.month, 3); XCTAssertEqual(c.day, 24)
        XCTAssertEqual(c.hour, 10); XCTAssertEqual(c.minute, 30)
    }

    func testParsesISO8601WithoutFractionalSeconds() throws {
        let msg = try decodeMessage(receivedOn: "2025-03-24T10:30:00Z")
        XCTAssertNotEqual(msg.date, .distantPast, "Plain ISO-8601 date must parse.")
        XCTAssertEqual(utcComponents(msg.date).day, 24)
    }

    func testParsesRFC2822Date() throws {
        let msg = try decodeMessage(receivedOn: "Mon, 24 Mar 2025 10:30:00 +0000")
        XCTAssertNotEqual(msg.date, .distantPast, "RFC-2822 date must parse via the cached fallback formatters.")
        let c = utcComponents(msg.date)
        XCTAssertEqual(c.year, 2025); XCTAssertEqual(c.month, 3); XCTAssertEqual(c.day, 24)
    }

    func testUnparseableDateFallsBackToDistantPast() throws {
        let msg = try decodeMessage(receivedOn: "not-a-date")
        XCTAssertEqual(msg.date, .distantPast,
            "An unparseable date must sort to the bottom (distantPast), not silently become 'now'.")
    }
}

// MARK: - URLProtocol stub for EmailService tests

final class EmailServiceURLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responder: ((URLRequest) -> (HTTPURLResponse, Data))?

    static func register() {
        URLProtocol.registerClass(EmailServiceURLProtocolStub.self)
    }

    static func unregister() {
        responder = nil
        URLProtocol.unregisterClass(EmailServiceURLProtocolStub.self)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let responder = EmailServiceURLProtocolStub.responder else {
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
