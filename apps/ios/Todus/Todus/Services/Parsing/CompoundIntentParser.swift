import Foundation

/// Parses natural-language input that may contain multiple intents (event + tasks).
/// Example: "Träffa Johan kl 13 imorgon och maila honom presentationen innan"
/// → event "Träffa Johan" at 13:00 tomorrow
/// → task "Maila honom presentationen" due at 12:45 tomorrow (15 min before anchor)
struct CompoundIntentParser {

    enum IntentType { case event, task, email }

    struct ParsedIntent {
        let type: IntentType
        let title: String
        let date: Date?
    }

    // MARK: - Public API

    /// Returns > 1 element when a compound input is detected; returns 1 element for simple inputs.
    static func parse(
        text: String,
        now: Date = .now,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> [ParsedIntent] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = splitAtConjunctions(trimmed, locale: locale)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isPureCommandPhrase($0, locale: locale) }

        guard segments.count > 1 else {
            guard !segments.isEmpty else { return [] }
            let textToParse = segments.first ?? trimmed
            let parsed = LocalTaskParsingService.parseImmediate(
                rawText: textToParse, now: now, locale: locale, timeZone: timeZone
            )
            return [ParsedIntent(
                type: classifyIntent(textToParse, locale: locale),
                title: parsed.title,
                date: parsed.dueDate
            )]
        }

        // First pass: parse each segment independently
        var segmentResults: [(type: IntentType, title: String, date: Date?, original: String)] = []
        for segment in segments {
            let parsed = LocalTaskParsingService.parseImmediate(
                rawText: segment, now: now, locale: locale, timeZone: timeZone
            )
            let type = classifyIntent(segment, locale: locale)
            segmentResults.append((
                type: type,
                title: parsed.title,
                date: parsed.dueDate,
                original: segment
            ))
        }

        // Second pass: resolve relative date references using anchor from first dated segment
        let anchorDate = segmentResults.first(where: { $0.date != nil })?.date

        var calendar = Calendar.current
        calendar.timeZone = timeZone

        var finalIntents: [ParsedIntent] = []
        for result in segmentResults {
            var resolvedDate = result.date

            if resolvedDate == nil, let anchor = anchorDate {
                let lower = result.original.lowercased(with: locale)
                if containsBeforeReference(lower) {
                    // "Innan"/"before" → 15 minutes before anchor
                    resolvedDate = calendar.date(byAdding: .minute, value: -15, to: anchor)
                } else if containsAfterReference(lower) {
                    // "Efteråt"/"after" → 15 minutes after anchor
                    resolvedDate = calendar.date(byAdding: .minute, value: 15, to: anchor)
                } else if containsSoonReference(lower) {
                    // "Snart"/"soon" → 1 hour before anchor
                    resolvedDate = calendar.date(byAdding: .hour, value: -1, to: anchor)
                }
                // Clean relative-ref words from title
            }

            // Strip relative-ref words from title
            let cleanTitle = stripRelativeRefWords(result.title, locale: locale)
            finalIntents.append(ParsedIntent(
                type: result.type,
                title: cleanTitle.isEmpty ? result.title : cleanTitle,
                date: resolvedDate
            ))
        }

        return finalIntents
    }

    // MARK: - Intent classification

    private static func matchesWord(_ word: String, in text: String) -> Bool {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isLikelyClauseStarter(_ text: String, locale: Locale) -> Bool {
        let lower = text.lowercased(with: locale)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let starterKeywords = [
            "maila", "email", "reply", "skicka", "send", "ring", "call",
            "träffa", "möt", "meet", "book", "boka", "schedule",
            "create", "skapa", "add", "lägg till"
        ]

        if starterKeywords.contains(where: { matchesWord($0, in: lower) }) {
            return true
        }

        let prefixedPattern = #"^(?:sedan|then)\s+\p{L}+"#
        if lower.range(of: prefixedPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            let trimmed = lower.replacingOccurrences(
                of: #"^(?:sedan|then)\s+"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            return starterKeywords.contains(where: { matchesWord($0, in: trimmed) })
        }

        return false
    }

    private static func classifyIntent(_ text: String, locale: Locale) -> IntentType {
        let lower = text.lowercased(with: locale)

        // Email keywords — check first since emails can mention events
        let emailKeywords = ["maila", "mail", "email", "skicka mail", "send email", "reply"]
        for kw in emailKeywords where matchesWord(kw, in: lower) { return .email }

        // Event keywords: meeting/social verbs and nouns
        let eventKeywords = [
            // Swedish
            "träffa", "träff", "möt", "möte", "lunch", "middag", "frukost",
            "dejt", "fika", "mingel", "samtal", "session", "föredrag",
            "presentation", "konferens", "intervju", "intervjua",
            // English
            "meet", "meeting", "dinner", "breakfast",
            "coffee", "date", "conference", "interview",
        ]
        for kw in eventKeywords where matchesWord(kw, in: lower) { return .event }

        return .task
    }

    // MARK: - Conjunction splitting

    /// Splits at "och"/"and" only when they appear as whole words between clauses.
    private static func splitAtConjunctions(_ text: String, locale: Locale) -> [String] {
        let pattern = #"\s+(?:och|and)\s+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return [text]
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, range: range)

        guard !matches.isEmpty else { return [text] }

        var segments: [String] = []
        var lastEnd = 0
        for match in matches {
            // Guard against negative substring length when matches overlap; only
            // collect a segment when there is actual text between conjunctions.
            let length = match.range.location - lastEnd
            guard length >= 0 else { continue }
            let segment = nsText.substring(with: NSRange(location: lastEnd, length: length))
            let nextSegmentStart = NSMaxRange(match.range)
            let remaining = nsText.substring(from: nextSegmentStart)

            if isLikelyClauseStarter(remaining, locale: locale) {
                segments.append(segment)
                lastEnd = nextSegmentStart
            }
        }
        segments.append(nsText.substring(from: lastEnd))

        return segments
    }

    // MARK: - Command word filtering

    /// Returns true if the segment is purely a command phrase with no content (e.g., "skapa dem").
    private static func isPureCommandPhrase(_ text: String, locale: Locale) -> Bool {
        let lower = text.lowercased(with: locale)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?,"))

        let commandPhrases = [
            // Swedish
            "skapa", "skapa dem", "skapa den", "skapa det", "skapa alla",
            "lägg till", "lägg till dem", "gör det", "gör dem",
            "och skapa", "spara", "spara det",
            // English
            "create", "create them", "create it", "add it", "save it",
            "do it", "make it",
        ]
        return commandPhrases.contains(lower)
    }

    // MARK: - Relative time references

    /// Word-boundary token check — avoids substring false positives such as
    /// "innan" matching inside "innanför" or "after" matching "afterthought".
    /// Multi-word phrases are escaped and matched literally with \b boundaries.
    private static func containsToken(_ token: String, in text: String) -> Bool {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: token))\\b"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func containsBeforeReference(_ lower: String) -> Bool {
        let tokens = ["innan", "before", "dessförinnan", "i förväg", "i forvag", "i förhand"]
        return tokens.contains(where: { containsToken($0, in: lower) })
    }

    private static func containsAfterReference(_ lower: String) -> Bool {
        let tokens = ["efteråt", "efterat", "efter det", "after", "afterwards"]
        if tokens.contains(where: { containsToken($0, in: lower) }) { return true }
        let senPattern = #"\bsen\b"#
        let sedanPattern = #"\bsedan\b"#
        return lower.range(of: senPattern, options: .regularExpression) != nil
            || lower.range(of: sedanPattern, options: .regularExpression) != nil
    }

    private static func containsSoonReference(_ lower: String) -> Bool {
        let tokens = ["snart", "soon"]
        return tokens.contains(where: { containsToken($0, in: lower) })
    }

    private static func stripRelativeRefWords(_ title: String, locale: Locale) -> String {
        var result = title
        let safePhrases = [
            "innan", "before", "efteråt", "efterat", "after", "afterwards",
            "dessförinnan", "snart", "soon", "i förväg", "i forvag",
            "i förhand", "i forhand", "sedan", "efter det",
        ]
        for word in safePhrases {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        result = result.replacingOccurrences(
            of: #"\bsen\b"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return result
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?,"))
    }
}
