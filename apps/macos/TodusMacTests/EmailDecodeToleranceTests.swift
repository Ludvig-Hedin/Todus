import XCTest
@testable import Todus

/// Regression tests for email model decoding tolerance.
///
/// Root cause these guard against: `mail.get` returns every message of a thread in a
/// single payload. Before these fixes a single malformed message (null/missing
/// `sender`, null `email`) threw a `DecodingError` that aborted the *entire* thread
/// decode — surfacing to the user as "errors when entering email threads".
///
/// A runnable, Xcode-free mirror of the thread-level test lives in
/// `scripts/run-email-decode-tests.sh`.
final class EmailDecodeToleranceTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - EmailSender

    func testSenderNameAndEmail() throws {
        let s = try decode(EmailSender.self, #"{"name":"Ada","email":"ada@x.com"}"#)
        XCTAssertEqual(s.name, "Ada")
        XCTAssertEqual(s.email, "ada@x.com")
    }

    func testSenderMissingNameFallsBackToEmail() throws {
        let s = try decode(EmailSender.self, #"{"email":"a@x.com"}"#)
        XCTAssertEqual(s.name, "a@x.com")
    }

    func testSenderNullEmailDoesNotThrow() throws {
        let s = try decode(EmailSender.self, #"{"name":"Sys","email":null}"#)
        XCTAssertEqual(s.email, "")
        XCTAssertEqual(s.name, "Sys")
    }

    func testSenderMissingEmailDoesNotThrow() throws {
        let s = try decode(EmailSender.self, #"{"name":"Sys"}"#)
        XCTAssertEqual(s.email, "")
    }

    // MARK: - EmailMessage

    func testFullMessageDecode() throws {
        let json = #"{"id":"m1","threadId":"t1","sender":{"name":"A","email":"a@x.com"},"decodedBody":"<p>hi</p>","receivedOn":"2025-03-24T10:30:00Z"}"#
        let m = try decode(EmailMessage.self, json)
        XCTAssertEqual(m.id, "m1")
        XCTAssertEqual(m.from.email, "a@x.com")
        XCTAssertEqual(m.body, "<p>hi</p>")
    }

    func testMessageMissingSenderUsesPlaceholder() throws {
        let m = try decode(EmailMessage.self, #"{"id":"m2","threadId":"t1","decodedBody":"body"}"#)
        XCTAssertEqual(m.from.name, "Unknown sender")
        XCTAssertEqual(m.from.email, "")
    }

    func testMessageUnparseableDateIsDistantPast() throws {
        let m = try decode(EmailMessage.self, #"{"id":"m3","sender":{"email":"a@x.com"},"receivedOn":"not-a-date"}"#)
        XCTAssertEqual(m.date, .distantPast)
    }

    func testMessageFractionalISODateParses() throws {
        let m = try decode(EmailMessage.self, #"{"id":"m4","sender":{"email":"a@x.com"},"receivedOn":"2025-03-24T10:30:00.500Z"}"#)
        XCTAssertGreaterThan(m.date, .distantPast)
    }

    // MARK: - GetThreadResponse (the core "error entering thread" regression)

    func testOneMalformedMessageDoesNotSinkWholeThread() throws {
        let json = """
        {"messages":[
          {"id":"a","sender":{"email":"a@x.com"},"decodedBody":"one"},
          {"sender":{"email":"b@x.com"},"decodedBody":"NO ID - malformed"},
          {"id":"c","sender":{"email":"c@x.com"},"decodedBody":"three"}
        ]}
        """
        let t = try decode(GetThreadResponse.self, json)
        XCTAssertEqual(t.messages.count, 2, "malformed (id-less) message should be dropped, not abort the thread")
        XCTAssertEqual(t.messages.map(\.id), ["a", "c"])
    }

    func testEmptyThreadDecodes() throws {
        let t = try decode(GetThreadResponse.self, #"{"messages":[]}"#)
        XCTAssertTrue(t.messages.isEmpty)
    }

    func testFailableDecodableDropsBadElement() throws {
        let arr = try decode([FailableDecodable<EmailMessage>].self,
                             #"[{"id":"ok","sender":{"email":"a@x.com"}},{"bogus":true}]"#)
        XCTAssertEqual(arr.compactMap(\.value).count, 1)
    }
}
