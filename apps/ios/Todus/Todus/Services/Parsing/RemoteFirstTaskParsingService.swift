import Foundation

/// Networking seam — `RemoteFirstTaskParsingService` calls the remote NLP edge
/// function through this protocol so unit tests can stub success / failure
/// without making a real HTTPS call. The production
/// `SupabaseEdgeFunctionClient` conforms via the extension at the bottom of
/// `SupabaseEdgeFunctionClient.swift`.
protocol RemoteTaskParsingTransport: Sendable {
    func invokeParse(path: String, body: ParseTasksRequest) async throws -> ParseTasksResponse
}

struct RemoteFirstTaskParsingService: TaskParsingService {
    private let configuration: AppConfiguration
    private let client: RemoteTaskParsingTransport?
    private let fallback: LocalTaskParsingService

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        if configuration.hasRemoteBackend {
            client = SupabaseEdgeFunctionClient(configuration: configuration)
        } else {
            client = nil
        }
        fallback = LocalTaskParsingService()
    }

    /// Internal init that accepts an injected `RemoteTaskParsingTransport`.
    /// Used by unit tests to assert the remote-succeeds and
    /// remote-fails-→-local-fallback branches without spinning up a real
    /// `SupabaseEdgeFunctionClient`.
    init(configuration: AppConfiguration, client: RemoteTaskParsingTransport?) {
        self.configuration = configuration
        self.client = client
        self.fallback = LocalTaskParsingService()
    }

    /// Local-only compound parse. Useful when callers (e.g. CreateSheet) need to
    /// split an input into multiple intents (`task + event + email`) without
    /// involving the remote NLP service. Routed through the new
    /// `CompoundIntentParser` so date anchors and relative ("innan" / "efter")
    /// resolution stay consistent with the macOS shell.
    func parseCompoundLocally(
        rawText: String,
        now: Date = .now,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> [CompoundIntentParser.ParsedIntent] {
        CompoundIntentParser.parse(text: rawText, now: now, locale: locale, timeZone: timeZone)
    }

    func parse(rawText: String, locale: Locale, timeZone: TimeZone, installID: String) async -> ParsedTaskResult {
        guard let client else {
            // No remote configured — local-only is expected, not a degradation, so don't
            // mark these results as low confidence.
            return await fallback.parse(rawText: rawText, locale: locale, timeZone: timeZone, installID: installID)
        }

        let request = ParseTasksRequest(
            rawText: rawText,
            localeIdentifier: locale.identifier,
            timeZoneIdentifier: timeZone.identifier,
            installID: installID,
            preferredModels: configuration.preferredModels
        )

        do {
            let response: ParseTasksResponse = try await client.invokeParse(
                path: configuration.parseFunctionPath,
                body: request
            )
            if let first = response.tasks.first {
                // Preserve the remote's own `lowConfidence` signal. Previously this
                // returned `first` as-is, which is fine, but a future change to
                // `ParsedTaskResult` defaulting `lowConfidence` to false would have
                // silently dropped the flag — make the propagation explicit.
                // (Bug H7.)
                return ParsedTaskResult(
                    title: first.title,
                    dueDate: first.dueDate,
                    confidence: first.confidence,
                    originalText: first.originalText,
                    suggestedFolderName: first.suggestedFolderName,
                    lowConfidence: first.lowConfidence
                )
            }
            // Empty response = the remote couldn't extract any task. Falling through to the
            // local parser is still useful, but the result is degraded — flag it.
            AppLogger.shared.log(
                "RemoteFirstTaskParsingService: remote returned no tasks, falling back to local NLP"
            )
        } catch {
            AppLogger.shared.log(
                "RemoteFirstTaskParsingService: remote parse failed (\(error.localizedDescription)), falling back to local NLP"
            )
            let local = await fallback.parse(rawText: rawText, locale: locale, timeZone: timeZone, installID: installID)
            return Self.markLowConfidence(local)
        }

        let local = await fallback.parse(rawText: rawText, locale: locale, timeZone: timeZone, installID: installID)
        return Self.markLowConfidence(local)
    }

    /// Returns a copy of the local parser's result with `lowConfidence` set to true so
    /// callers (TaskCaptureService, AI chat) can surface a soft warning in the UI.
    private static func markLowConfidence(_ result: ParsedTaskResult) -> ParsedTaskResult {
        ParsedTaskResult(
            title: result.title,
            dueDate: result.dueDate,
            confidence: result.confidence,
            originalText: result.originalText,
            suggestedFolderName: result.suggestedFolderName,
            lowConfidence: true
        )
    }
}
