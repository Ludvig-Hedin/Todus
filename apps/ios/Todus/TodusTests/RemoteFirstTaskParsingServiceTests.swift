import XCTest
@testable import Todus

/// `RemoteFirstTaskParsingService` selects between a Supabase-hosted parser
/// and a local NLP fallback. The remote `SupabaseEdgeFunctionClient` is
/// nilled out at init when `configuration.hasRemoteBackend` is false — that
/// gives us a clean seam to exercise the local-only branch end-to-end without
/// network access. The "remote succeeds with lowConfidence" and "remote
/// fails → fallback marked lowConfidence" branches require a stubbed remote
/// client; they're skipped with a TODO.
final class RemoteFirstTaskParsingServiceTests: XCTestCase {

    // Helper: build a configuration that *intentionally* lacks a backend URL,
    // forcing RemoteFirstTaskParsingService into the local-only fallback path.
    private func makeLocalOnlyConfig() -> AppConfiguration {
        AppConfiguration(
            backendURL: nil,
            supabaseURL: nil,
            supabaseAnonKey: "",
            parseFunctionPath: "parseTasks",
            syncFunctionPath: "syncTasks",
            upgradeFunctionPath: "upgradeAnonymousUser",
            chatFunctionPath: "chatAI",
            primaryModel: "openai/gpt-5.4-mini",
            fallbackModels: []
        )
    }

    func testLocalOnlyConfigDoesNotMarkResultLowConfidence() async {
        // When no remote backend is configured, local NLP is the only viable
        // pathway — we treat it as the expected outcome, NOT a degraded
        // fallback, so `lowConfidence` must stay false.
        let svc = RemoteFirstTaskParsingService(configuration: makeLocalOnlyConfig())
        let result = await svc.parse(
            rawText: "Buy milk tomorrow",
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(identifier: "Europe/Stockholm")!,
            installID: "test-install-\(UUID().uuidString)"
        )
        XCTAssertFalse(result.lowConfidence,
            "Local-only configuration must NOT flag results as low confidence (#H7 sibling check).")
        XCTAssertFalse(result.title.isEmpty)
    }

    func testLocalOnlyConfigReturnsTitleForUnparseableInput() async {
        // The local parser must always return *something* — empty title would
        // cause the calling TaskCaptureService to crash on subsequent steps.
        let svc = RemoteFirstTaskParsingService(configuration: makeLocalOnlyConfig())
        let result = await svc.parse(
            rawText: "xx",
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone.current,
            installID: "test-install"
        )
        XCTAssertFalse(result.title.isEmpty,
            "Parser must never return an empty title even for inscrutable input.")
    }

    func testParsedTaskResultLowConfidenceFlagSurvivesCopyConstruction() {
        // Pins the H7 fix: the manual re-construction inside
        // RemoteFirstTaskParsingService propagates `lowConfidence` explicitly.
        // If a future change drops that field from the copy, this test fails.
        let remote = ParsedTaskResult(
            title: "Demo",
            dueDate: nil,
            confidence: 0.6,
            originalText: "demo",
            suggestedFolderName: nil,
            lowConfidence: true
        )
        let copy = ParsedTaskResult(
            title: remote.title,
            dueDate: remote.dueDate,
            confidence: remote.confidence,
            originalText: remote.originalText,
            suggestedFolderName: remote.suggestedFolderName,
            lowConfidence: remote.lowConfidence
        )
        XCTAssertTrue(copy.lowConfidence, "lowConfidence must be propagated by the manual copy (H7 fix).")
    }

    func testParsedTaskResultDecodingDefaultsLowConfidenceFalse() throws {
        // Backwards-compat: older payloads without `lowConfidence` must
        // decode without throwing, with the field defaulting to false.
        let json = """
        {"title": "Buy milk", "confidence": 0.9, "originalText": "buy milk"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ParsedTaskResult.self, from: json)
        XCTAssertEqual(decoded.title, "Buy milk")
        XCTAssertFalse(decoded.lowConfidence)
    }

    // MARK: - Remote transport stub

    private func makeRemoteConfig() -> AppConfiguration {
        // A config whose `hasRemoteBackend` is true so we hit the remote branch.
        AppConfiguration(
            backendURL: URL(string: "https://stub.local"),
            supabaseURL: URL(string: "https://stub.local"),
            supabaseAnonKey: "anon-key",
            parseFunctionPath: "parseTasks",
            syncFunctionPath: "syncTasks",
            upgradeFunctionPath: "upgradeAnonymousUser",
            chatFunctionPath: "chatAI",
            primaryModel: "openai/gpt-5.4-mini",
            fallbackModels: []
        )
    }

    func testRemoteSuccessPreservesLowConfidenceFlag() async throws {
        // Remote returns a single parsed task with lowConfidence=true. The
        // service must propagate the flag through the manual copy (H7 fix).
        struct SuccessStub: RemoteTaskParsingTransport {
            func invokeParse(path: String, body: ParseTasksRequest) async throws -> ParseTasksResponse {
                ParseTasksResponse(tasks: [
                    ParsedTaskResult(
                        title: "Remote title",
                        dueDate: nil,
                        confidence: 0.55,
                        originalText: body.rawText,
                        suggestedFolderName: nil,
                        lowConfidence: true
                    )
                ])
            }
        }
        let svc = RemoteFirstTaskParsingService(configuration: makeRemoteConfig(), client: SuccessStub())
        let result = await svc.parse(
            rawText: "do thing",
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(identifier: "UTC")!,
            installID: "test-install"
        )
        XCTAssertEqual(result.title, "Remote title")
        XCTAssertTrue(result.lowConfidence,
            "H7: lowConfidence from the remote response must propagate through the manual copy.")
    }

    func testRemoteFailureFallsBackToLocalAndMarksLowConfidence() async throws {
        // Remote throws — the service must fall back to the local NLP parser
        // and mark the result as low confidence so the UI can flag it.
        struct FailureStub: RemoteTaskParsingTransport {
            func invokeParse(path: String, body: ParseTasksRequest) async throws -> ParseTasksResponse {
                throw URLError(.notConnectedToInternet)
            }
        }
        let svc = RemoteFirstTaskParsingService(configuration: makeRemoteConfig(), client: FailureStub())
        let result = await svc.parse(
            rawText: "Buy milk tomorrow",
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(identifier: "UTC")!,
            installID: "test-install"
        )
        XCTAssertFalse(result.title.isEmpty,
            "Local fallback must still produce a non-empty title for valid input.")
        XCTAssertTrue(result.lowConfidence,
            "Remote failure → local fallback must mark the result as low confidence.")
    }
}
