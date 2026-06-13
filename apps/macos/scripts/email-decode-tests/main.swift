import Foundation

// Stub AppLogger so the real EmailModels.swift compiles standalone (no Xcode target).
final class AppLogger {
    static let shared = AppLogger()
    func log(_ s: String) {}
}

// Mirror of the tolerant decode logic added to EmailService.swift (GetThreadResponse
// + FailableDecodable). Kept in sync here so the "one bad message must not sink the
// whole thread" regression is runnable without an Xcode test target. The XCTest copy
// in TodusMacTests/ exercises the real GetThreadResponse via @testable import.
struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try? container.decode(T.self)
    }
}

struct ThreadResponseUnderTest: Decodable {
    let messages: [EmailMessage]
    private enum CodingKeys: String, CodingKey { case messages }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.messages = (try? c.decode([FailableDecodable<EmailMessage>].self, forKey: .messages))?
            .compactMap(\.value) ?? []
    }
}

// ---- Minimal assert harness ----
var passed = 0, failed = 0
func check(_ name: String, _ cond: Bool) {
    if cond { passed += 1; print("  ✓ \(name)") }
    else { failed += 1; print("  ✗ FAIL: \(name)") }
}
func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T? {
    try? JSONDecoder().decode(T.self, from: Data(json.utf8))
}

print("EmailSender decode tolerance")
if let s = decode(EmailSender.self, #"{"name":"Ada","email":"ada@x.com"}"#) {
    check("name+email decode", s.name == "Ada" && s.email == "ada@x.com")
} else { check("name+email decode", false) }
if let s = decode(EmailSender.self, #"{"email":"a@x.com"}"#) {
    check("missing name falls back to email", s.name == "a@x.com" && s.email == "a@x.com")
} else { check("missing name falls back to email", false) }
// REGRESSION: null email no longer throws (was a hard decode failure that aborted the thread)
if let s = decode(EmailSender.self, #"{"name":"Sys","email":null}"#) {
    check("null email tolerated", s.email == "" && s.name == "Sys")
} else { check("null email tolerated", false) }
if let s = decode(EmailSender.self, #"{"name":"Sys"}"#) {
    check("missing email tolerated", s.email == "")
} else { check("missing email tolerated", false) }

print("EmailMessage decode tolerance")
let full = #"{"id":"m1","threadId":"t1","sender":{"name":"A","email":"a@x.com"},"decodedBody":"<p>hi</p>","receivedOn":"2025-03-24T10:30:00Z"}"#
if let m = decode(EmailMessage.self, full) {
    check("full message decode", m.id == "m1" && m.from.email == "a@x.com" && m.body == "<p>hi</p>")
} else { check("full message decode", false) }
// REGRESSION: message with MISSING sender no longer throws -> placeholder sender
let noSender = #"{"id":"m2","threadId":"t1","decodedBody":"body"}"#
if let m = decode(EmailMessage.self, noSender) {
    check("missing sender -> placeholder", m.from.name == "Unknown sender" && m.from.email == "")
} else { check("missing sender -> placeholder", false) }
let badDate = #"{"id":"m3","sender":{"email":"a@x.com"},"receivedOn":"not-a-date"}"#
if let m = decode(EmailMessage.self, badDate) {
    check("unparseable date -> distantPast", m.date == .distantPast)
} else { check("unparseable date -> distantPast", false) }
let frac = #"{"id":"m4","sender":{"email":"a@x.com"},"receivedOn":"2025-03-24T10:30:00.500Z"}"#
check("fractional ISO date parses", decode(EmailMessage.self, frac)?.date ?? .distantPast > .distantPast)

print("Thread response: one bad message must not sink the whole thread")
// REGRESSION (the literal "error entering thread" report): middle message is malformed
// (no id). Whole-thread decode must survive, dropping only the bad element.
let mixed = """
{"messages":[
  {"id":"a","sender":{"email":"a@x.com"},"decodedBody":"one"},
  {"sender":{"email":"b@x.com"},"decodedBody":"NO ID - malformed"},
  {"id":"c","sender":{"email":"c@x.com"},"decodedBody":"three"}
]}
"""
if let t = decode(ThreadResponseUnderTest.self, mixed) {
    check("malformed message dropped, others survive", t.messages.count == 2)
    check("surviving messages are the valid ones", t.messages.map(\.id) == ["a", "c"])
} else {
    check("malformed message dropped, others survive", false)
    check("surviving messages are the valid ones", false)
}
check("empty thread decodes", decode(ThreadResponseUnderTest.self, #"{"messages":[]}"#)?.messages.isEmpty == true)

print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
