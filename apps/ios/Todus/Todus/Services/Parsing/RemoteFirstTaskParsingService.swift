import Foundation

struct RemoteFirstTaskParsingService: TaskParsingService {
    private let configuration: AppConfiguration
    private let client: SupabaseEdgeFunctionClient?
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
            let response: ParseTasksResponse = try await client.invoke(
                path: configuration.parseFunctionPath,
                body: request
            )
            if let first = response.tasks.first {
                return first
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
