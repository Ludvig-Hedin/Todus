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
        } catch {
            return await fallback.parse(rawText: rawText, locale: locale, timeZone: timeZone, installID: installID)
        }

        return await fallback.parse(rawText: rawText, locale: locale, timeZone: timeZone, installID: installID)
    }
}
