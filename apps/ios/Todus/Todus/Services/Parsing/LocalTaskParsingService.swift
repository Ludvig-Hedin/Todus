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
        let nsRange = NSRange(location: 0, length: trimmed.utf16.count)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone

        var consumedRanges: [NSRange] = []
        var baseDate = now
        var confidence = 0.52
        var foundDateKeyword = false

        // Step 1: detect relative date keywords
        let relativeMarkers: [(String, Int)] = [
            ("imorgon", 1),
            ("tomorrow", 1),
            ("idag", 0),
            ("today", 0)
        ]
        for (token, offset) in relativeMarkers {
            if let range = trimmed.range(
                of: token,
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: locale
            ) {
                consumedRanges.append(NSRange(range, in: trimmed))
                baseDate = cal.date(byAdding: .day, value: offset, to: now) ?? now
                confidence = 0.86
                foundDateKeyword = true
                break
            }
        }

        // Step 2: detect weekday references (Swedish + English)
        let weekdayMarkers: [(String, Int)] = [
            ("måndag", 2), ("mandag", 2), ("monday", 2),
            ("tisdag", 3), ("tuesday", 3),
            ("onsdag", 4), ("wednesday", 4),
            ("torsdag", 5), ("thursday", 5),
            ("fredag", 6), ("friday", 6),
            ("lördag", 7), ("lordag", 7), ("saturday", 7),
            ("söndag", 1), ("sondag", 1), ("sunday", 1),
        ]
        // Only apply weekday if no relative date keyword was found
        if !foundDateKeyword {
            let currentWeekday = cal.component(.weekday, from: now)
            for (token, targetWeekday) in weekdayMarkers {
                if let range = trimmed.range(
                    of: token,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: locale
                ) {
                    consumedRanges.append(NSRange(range, in: trimmed))
                    var daysAhead = targetWeekday - currentWeekday
                    if daysAhead <= 0 { daysAhead += 7 }
                    baseDate = cal.date(byAdding: .day, value: daysAhead, to: now) ?? now
                    confidence = 0.82
                    foundDateKeyword = true
                    break
                }
            }
        }

        // Step 3: find time — try patterns in priority order.
        // Use the explicit `foundDateKeyword` flag instead of `baseDate != now`,
        // which is false for "today"/"idag" (offset 0 means baseDate == now)
        // and silently disables tail-time parsing for those phrases.
        var dueDate: Date? = nil
        // True when the user stated an explicit time-of-day (e.g. "kl 13", "2pm"), as
        // opposed to a bare day where we synthesize a default time. (B-036.)
        var hasExplicitTime = false
        let hasDateKeyword = foundDateKeyword

        if let match = findTimeMatch(in: trimmed, range: nsRange, hasDateKeyword: hasDateKeyword) {
            let (hours, minutes, matchRange) = extractHoursMinutes(from: match, in: trimmed)
            if let hours {
                consumedRanges.append(matchRange)
                dueDate = calendarDate(baseDate: baseDate, hour: hours, minute: minutes, timeZone: timeZone)
                // Only count as a stated time when the calendar actually resolved a date.
                hasExplicitTime = dueDate != nil
                // If no date keyword and the parsed time has already passed today, roll to tomorrow
                if !foundDateKeyword, let resolved = dueDate, resolved < now {
                    dueDate = cal.date(byAdding: .day, value: 1, to: resolved)
                }
                confidence = max(confidence, 0.9)
            }
        }

        // Step 4: date keyword but no time.
        // For "today"/"idag" with no time, default to (now + 2h) so notifications can fire.
        // For weekday/tomorrow keywords, use start of that day.
        if dueDate == nil, foundDateKeyword {
            let isToday = cal.isDate(baseDate, inSameDayAs: now)
            if isToday {
                dueDate = now.addingTimeInterval(2 * 60 * 60)
            } else {
                dueDate = cal.startOfDay(for: baseDate)
            }
            confidence = max(confidence, 0.72)
        }

        // Build cleaned title by removing all consumed token ranges
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
        if cleanedTitle.isEmpty { cleanedTitle = trimmed }

        return ParsedTaskResult(
            title: cleanedTitle,
            dueDate: dueDate,
            confidence: confidence,
            originalText: trimmed,
            suggestedFolderName: nil,
            hasTime: hasExplicitTime
        )
    }

    // MARK: - Time detection

    /// Try patterns in priority order. Returns the first match found.
    /// Priority:
    ///   1. Explicit prefix ("kl 13", "at 2:30", "@9") — handles Swedish time-before-date order
    ///   2. HH:MM colon format ("13:30") — unambiguous without prefix
    ///   3. Bare number at end of string — only safe when a date keyword was already found
    // Optional am/pm suffix at capture group 3
    private static let prefixedTimeRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?:kl\s*|at\s+|@\s*)([01]?\d|2[0-3])(?::([0-5]\d))?\s*(am|pm|a\.m\.|p\.m\.)?(?!\w)"#,
        options: [.caseInsensitive]
    )
    private static let colonTimeRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?<!\d)([01]?\d|2[0-3]):([0-5]\d)\s*(am|pm|a\.m\.|p\.m\.)?(?!\w)"#,
        options: [.caseInsensitive]
    )
    private static let tailTimeRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?<![:\d])([01]?\d|2[0-3])(?::([0-5]\d))?\s*(am|pm|a\.m\.|p\.m\.)?\s*$"#,
        options: [.caseInsensitive]
    )

    private static func findTimeMatch(
        in text: String,
        range: NSRange,
        hasDateKeyword: Bool
    ) -> NSTextCheckingResult? {
        if let m = prefixedTimeRegex?.firstMatch(in: text, range: range) { return m }
        if let m = colonTimeRegex?.firstMatch(in: text, range: range) { return m }
        if hasDateKeyword {
            return tailTimeRegex?.firstMatch(in: text, range: range)
        }
        return nil
    }

    private static func extractHoursMinutes(
        from match: NSTextCheckingResult,
        in text: String
    ) -> (hours: Int?, minutes: Int, matchRange: NSRange) {
        let hoursRange = match.range(at: 1)
        let minutesRange = match.range(at: 2)
        let meridiemRange = match.numberOfRanges > 3 ? match.range(at: 3) : NSRange(location: NSNotFound, length: 0)

        guard
            hoursRange.location != NSNotFound,
            let hoursSwiftRange = Range(hoursRange, in: text),
            var hours = Int(text[hoursSwiftRange])
        else {
            return (nil, 0, match.range)
        }

        let minutes: Int
        if minutesRange.location != NSNotFound,
           let minutesSwiftRange = Range(minutesRange, in: text) {
            minutes = Int(text[minutesSwiftRange]) ?? 0
        } else {
            minutes = 0
        }

        // Apply am/pm normalization when meridiem present.
        if meridiemRange.location != NSNotFound,
           let meridiemSwiftRange = Range(meridiemRange, in: text) {
            let meridiem = text[meridiemSwiftRange].lowercased().replacingOccurrences(of: ".", with: "")
            if meridiem == "pm" && hours < 12 {
                hours += 12
            } else if meridiem == "am" && hours == 12 {
                hours = 0
            }
        }

        return (hours, minutes, match.range)
    }

    // MARK: - Calendar helpers

    private static func calendarDate(baseDate: Date, hour: Int, minute: Int, timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = calendar.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)
    }

    private static func normalized(_ ranges: [NSRange]) -> [NSRange] {
        let sorted = ranges.sorted {
            $0.location == $1.location ? $0.length > $1.length : $0.location < $1.location
        }
        var result: [NSRange] = []
        for range in sorted {
            guard let last = result.last else { result.append(range); continue }
            let lastMax = NSMaxRange(last)
            let currentMax = NSMaxRange(range)
            if range.location <= lastMax {
                result[result.count - 1] = NSRange(
                    location: last.location,
                    length: max(lastMax, currentMax) - last.location
                )
            } else {
                result.append(range)
            }
        }
        return result
    }
}
