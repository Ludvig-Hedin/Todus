import Foundation

protocol TaskParsingService: Sendable {
    func parse(rawText: String, locale: Locale, timeZone: TimeZone, installID: String) async -> ParsedTaskResult
}
