import Foundation

struct LocalTaskParsingService: TaskParsingService {
    func parse(rawText: String, locale: Locale, timeZone: TimeZone, installID: String) async -> ParsedTaskResult {
        Self.parseImmediate(rawText: rawText, now: .now, locale: locale, timeZone: timeZone)
    }

    static func parseImmediate(
        rawText: String,
        now: Date,
        locale: Locale,
        timeZone: TimeZone
    ) -> ParsedTaskResult {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased(with: locale)
        let nsRange = NSRange(location: 0, length: lowered.utf16.count)

        var consumedRanges: [NSRange] = []
        var baseDate = now
        var confidence = 0.52

        let relativeMarkers: [(String, Int)] = [
            ("imorgon", 1),
            ("tomorrow", 1),
            ("idag", 0),
            ("today", 0)
        ]

        for (token, offset) in relativeMarkers {
            if let range = lowered.range(of: token) {
                consumedRanges.append(NSRange(range, in: lowered))
                baseDate = Calendar.current.date(byAdding: .day, value: offset, to: now) ?? now
                confidence = 0.86
            }
        }

        let timeRegex = (try? NSRegularExpression(
            pattern: #"(?:(?:imorgon|tomorrow|idag|today)\s+)?(?:kl\s*|at\s+|@\s*)?([01]?\d|2[0-3])(?::([0-5]\d))?$"#
        )) ?? NSRegularExpression()
        var dueDate: Date?

        if let match = timeRegex.firstMatch(in: lowered, options: [], range: nsRange) {
            let hoursRange = match.range(at: 1)
            let minutesRange = match.range(at: 2)
            if
                let hoursSwiftRange = Range(hoursRange, in: lowered),
                let hours = Int(lowered[hoursSwiftRange])
            {
                let minutes: Int
                if let minutesSwiftRange = Range(minutesRange, in: lowered) {
                    minutes = Int(lowered[minutesSwiftRange]) ?? 0
                } else {
                    minutes = 0
                }

                consumedRanges.append(match.range)
                dueDate = calendarDate(baseDate: baseDate, hour: hours, minute: minutes, timeZone: timeZone)

                if dueDate == nil {
                    dueDate = baseDate
                }

                if baseDate == now, let resolvedDueDate = dueDate, resolvedDueDate < now {
                    dueDate = Calendar.current.date(byAdding: .day, value: 1, to: resolvedDueDate)
                }

                confidence = max(confidence, 0.9)
            }
        }

        if dueDate == nil, baseDate != now {
            dueDate = Calendar.current.startOfDay(for: baseDate)
            confidence = max(confidence, 0.72)
        }

        let normalizedRanges = normalized(consumedRanges)

        var cleanedTitle = trimmed
        for range in normalizedRanges.sorted(by: { $0.location > $1.location }) {
            if let swiftRange = Range(range, in: cleanedTitle) {
                cleanedTitle.removeSubrange(swiftRange)
            }
        }

        cleanedTitle = cleanedTitle
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanedTitle.isEmpty {
            cleanedTitle = trimmed
        }

        return ParsedTaskResult(
            title: cleanedTitle,
            dueDate: dueDate,
            confidence: confidence,
            originalText: trimmed,
            suggestedFolderName: nil
        )
    }

    private static func calendarDate(baseDate: Date, hour: Int, minute: Int, timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var components = calendar.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)
    }

    private static func normalized(_ ranges: [NSRange]) -> [NSRange] {
        let sorted = ranges.sorted { lhs, rhs in
            if lhs.location == rhs.location {
                return lhs.length > rhs.length
            }
            return lhs.location < rhs.location
        }

        var result: [NSRange] = []
        for range in sorted {
            guard let last = result.last else {
                result.append(range)
                continue
            }

            let lastMax = NSMaxRange(last)
            let currentMax = NSMaxRange(range)
            if range.location <= lastMax {
                let merged = NSRange(location: last.location, length: max(lastMax, currentMax) - last.location)
                result[result.count - 1] = merged
            } else {
                result.append(range)
            }
        }

        return result
    }
}
