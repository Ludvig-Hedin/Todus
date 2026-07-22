import XCTest
@testable import Todus

final class ModelDownloadAttemptRegistryTests: XCTestCase {
    func testFinishingCancelledAttemptCannotClearReplacement() {
        var registry = ModelDownloadAttemptRegistry()
        let first = UUID()
        let replacement = UUID()

        _ = registry.begin(modelID: "model", attemptID: first)
        registry.cancel(modelID: "model")
        _ = registry.begin(modelID: "model", attemptID: replacement)

        XCTAssertFalse(registry.finish(modelID: "model", attemptID: first))
        XCTAssertTrue(registry.owns(modelID: "model", attemptID: replacement))
        XCTAssertTrue(registry.finish(modelID: "model", attemptID: replacement))
    }
}

/// Focused on the SSE framing helper that runs inside `runStep`. The
/// production path consumes bytes via `URLSession.bytes.lines`, which only
/// splits on `\n` and leaves trailing `\r` characters attached — the H14 fix
/// makes the parser strip those before checking the `data: ` prefix. These
/// tests pin that contract against the extracted `SSELineParser` helper.
final class AIChatServiceTests: XCTestCase {

    // MARK: - classify(line:)

    func testClassifyHandlesCRLFTrailingLine() {
        // Mimics what `bytes.lines` hands us for a CRLF-framed server: the
        // splitter consumes the `\n` but leaves the `\r` on the line.
        let event = SSELineParser.classify(line: "data: hello\r")
        XCTAssertEqual(event, .data("hello"))
    }

    func testClassifyHandlesLFOnlyLine() {
        // A non-CRLF server delivers lines without any trailing `\r`. The same
        // classifier must accept both framings.
        let event = SSELineParser.classify(line: "data: hello")
        XCTAssertEqual(event, .data("hello"))
    }

    func testClassifyDetectsDoneWithCRTrailingByte() {
        // The `[DONE]` sentinel was a key H14 regression candidate — if the
        // CR isn't stripped, this line falls into the `.data` branch and the
        // stream "completes" with a junk payload of `[DONE]\r`.
        XCTAssertEqual(SSELineParser.classify(line: "data: [DONE]\r"), .done)
    }

    func testClassifyDetectsDoneWithoutTrailingCR() {
        XCTAssertEqual(SSELineParser.classify(line: "data: [DONE]"), .done)
    }

    func testClassifySkipsNonDataLines() {
        // Heart-beat / comment / id lines must be ignored so the stream loop
        // keeps spinning without firing decode calls.
        XCTAssertEqual(SSELineParser.classify(line: ""), .skip)
        XCTAssertEqual(SSELineParser.classify(line: ":\r"), .skip)
        XCTAssertEqual(SSELineParser.classify(line: "event: ping"), .skip)
        XCTAssertEqual(SSELineParser.classify(line: "id: 42"), .skip)
    }

    func testClassifyPreservesJSONPayloadVerbatim() {
        // The payload must be returned exactly — `dropFirst(6)` removes the
        // `data: ` prefix and nothing else, even when the JSON itself contains
        // a `data: ` substring.
        let line = "data: {\"choices\":[{\"delta\":{\"content\":\"data: nested\"}}]}\r"
        guard case .data(let payload) = SSELineParser.classify(line: line) else {
            return XCTFail("Expected .data event for valid SSE line")
        }
        XCTAssertEqual(payload, "{\"choices\":[{\"delta\":{\"content\":\"data: nested\"}}]}")
    }

    // MARK: - splitChunk

    func testSplitChunkSplitsCompleteLinesAndCarriesResidual() {
        var residual = ""
        let lines = SSELineParser.splitChunk(
            "data: first\r\ndata: second\r\ndata: thi",
            residual: &residual
        )
        XCTAssertEqual(lines, ["data: first\r", "data: second\r"])
        XCTAssertEqual(residual, "data: thi", "Partial trailing line must be carried forward.")
    }

    func testSplitChunkConcatenatesAcrossChunkBoundary() {
        var residual = ""
        _ = SSELineParser.splitChunk("data: he", residual: &residual)
        XCTAssertEqual(residual, "data: he")

        let lines = SSELineParser.splitChunk("llo\r\ndata: world\r\n", residual: &residual)
        XCTAssertEqual(lines, ["data: hello\r", "data: world\r"])
        XCTAssertEqual(residual, "", "After a clean newline boundary the residual must drain.")
    }

    func testSplitChunkHandlesEmptyChunk() {
        var residual = "data: partial"
        let lines = SSELineParser.splitChunk("", residual: &residual)
        XCTAssertEqual(lines, [])
        XCTAssertEqual(residual, "data: partial")
    }

    // MARK: - End-to-end stream replay

    func testStreamReplayParsesMultipleEventsThenDONE() {
        // Replays the exact wire shape the production loop receives:
        //   data: {...}<CR><LF>
        //   data: {...}<CR><LF>
        //   data: [DONE]<CR><LF>
        // Build the stream explicitly with real CR / LF bytes — Swift's
        // multi-line string literals don't expand `\r` to CR, so an inline
        // literal would parse to the characters `\` + `r`.
        let CR = "\r"
        let LF = "\n"
        let lines = [
            "data: {\"choices\":[{\"delta\":{\"content\":\"hi\"}}]}",
            "data: {\"choices\":[{\"delta\":{\"content\":\" there\"}}]}",
            "data: [DONE]"
        ]
        let stream = lines.map { $0 + CR }.joined(separator: LF) + LF

        var events: [SSELineParser.Event] = []
        for line in stream.components(separatedBy: LF) {
            events.append(SSELineParser.classify(line: line))
        }

        let dataCount = events.filter { if case .data = $0 { return true } else { return false } }.count
        let doneCount = events.filter { $0 == .done }.count
        XCTAssertEqual(dataCount, 2, "Two `data:` payloads must parse out of the stream.")
        XCTAssertEqual(doneCount, 1, "The CR-terminated [DONE] sentinel must classify as .done.")
    }

    func testMalformedJSONInMiddleDoesNotAbort() {
        // Classifier only frames — JSON validity is the decoder's job. A
        // malformed payload still surfaces as `.data` so the outer loop can
        // try-decode and continue; nothing here should throw.
        let bogus = SSELineParser.classify(line: "data: {not-json}\r")
        guard case .data(let payload) = bogus else {
            return XCTFail("Malformed payloads must still framing-classify as .data")
        }
        XCTAssertEqual(payload, "{not-json}")

        // Subsequent valid event must classify normally.
        let next = SSELineParser.classify(line: "data: {\"choices\":[{\"delta\":{}}]}\r")
        XCTAssertNotEqual(next, .skip)
    }

    // MARK: - Internals that need a real AIChatService instance

    func testFlushTokenBufferBailsWhenStreamingMessageIDChanges() {
        // H12: if the captured messageID no longer matches the message that's
        // currently streaming (user retried / new turn started), the flush
        // must DROP the buffer rather than writing into the wrong message.
        let original = UUID()
        let newStreaming = UUID()

        // Stale capture — different message streaming now → must drop.
        XCTAssertEqual(
            AIChatService.classifyFlushDecision(
                messageID: original,
                currentStreamingMessageID: newStreaming,
                bufferIsEmpty: false,
                messageExists: true
            ),
            .drop,
            "H12: a streaming message id mismatch must drop the buffer to avoid cross-turn token leaks."
        )

        // Same capture — current streaming matches → write.
        XCTAssertEqual(
            AIChatService.classifyFlushDecision(
                messageID: original,
                currentStreamingMessageID: original,
                bufferIsEmpty: false,
                messageExists: true
            ),
            .write
        )

        // No-one streaming (e.g. final flush after stream end) — still write.
        XCTAssertEqual(
            AIChatService.classifyFlushDecision(
                messageID: original,
                currentStreamingMessageID: nil,
                bufferIsEmpty: false,
                messageExists: true
            ),
            .write
        )

        // Empty buffer → drop (nothing to write).
        XCTAssertEqual(
            AIChatService.classifyFlushDecision(
                messageID: original,
                currentStreamingMessageID: original,
                bufferIsEmpty: true,
                messageExists: true
            ),
            .drop
        )

        // Message no longer exists (e.g. user cleared the conversation) → drop.
        XCTAssertEqual(
            AIChatService.classifyFlushDecision(
                messageID: original,
                currentStreamingMessageID: nil,
                bufferIsEmpty: false,
                messageExists: false
            ),
            .drop
        )
    }

    // MARK: - Conversation autosave identity

    func testAutosaveSnapshotUpdatesReopenedConversationWithoutChangingIdentity() {
        let conversationID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let generatedID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_700_001_000)
        let original = AIChatConversation(
            id: conversationID,
            title: "Original",
            createdAt: createdAt,
            messages: [.init(role: "user", content: "First turn")]
        )
        let updatedMessages = [
            AIChatConversation.SavedMessage(role: "user", content: "First turn"),
            AIChatConversation.SavedMessage(role: "assistant", content: "First reply"),
            AIChatConversation.SavedMessage(role: "user", content: "Follow-up"),
        ]

        let result = AIChatService.conversationSaveSnapshot(
            currentConversationID: conversationID,
            currentConversationCreatedAt: createdAt,
            title: "Original",
            folderID: nil,
            messages: updatedMessages,
            savedConversations: [original],
            now: updatedAt,
            generatedID: generatedID
        )

        XCTAssertEqual(result.conversation.id, conversationID)
        XCTAssertEqual(result.conversation.createdAt, createdAt)
        XCTAssertEqual(result.conversation.updatedAt, updatedAt)
        XCTAssertEqual(result.savedConversations.count, 1)
        XCTAssertEqual(result.savedConversations[0].id, conversationID)
        XCTAssertEqual(result.savedConversations[0].messages.count, 3)
    }

    func testAutosaveSnapshotCreatesNewConversationWhenNoConversationIsOpen() {
        let generatedID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let now = Date(timeIntervalSince1970: 1_700_002_000)

        let result = AIChatService.conversationSaveSnapshot(
            currentConversationID: nil,
            currentConversationCreatedAt: nil,
            title: "New chat",
            folderID: nil,
            messages: [.init(role: "user", content: "Hello")],
            savedConversations: [],
            now: now,
            generatedID: generatedID
        )

        XCTAssertEqual(result.conversation.id, generatedID)
        XCTAssertEqual(result.conversation.createdAt, now)
        XCTAssertEqual(result.savedConversations.map(\.id), [generatedID])
    }
}
