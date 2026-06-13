import XCTest
@testable import Todus

final class LocalTaskParsingServiceTests: XCTestCase {
    func testSwedishTomorrowParsing() {
        let timeZone = TimeZone(identifier: "Europe/Stockholm")!
        let locale = Locale(identifier: "sv_SE")
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 23, hour: 9, minute: 0))!

        let result = LocalTaskParsingService.parseImmediate(
            rawText: "Buy milk imorgon 18",
            now: now,
            locale: locale,
            timeZone: timeZone
        )

        XCTAssertEqual(result.title, "Buy milk")
        XCTAssertNotNil(result.dueDate)

        let dueComponents = calendar.dateComponents(in: timeZone, from: result.dueDate!)
        XCTAssertEqual(dueComponents.day, 24)
        XCTAssertEqual(dueComponents.hour, 18)
        XCTAssertEqual(dueComponents.minute, 0)
    }

    func testEnglishTodayParsing() {
        let timeZone = TimeZone(identifier: "Europe/Stockholm")!
        let locale = Locale(identifier: "en_US")
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 23, hour: 9, minute: 0))!

        let result = LocalTaskParsingService.parseImmediate(
            rawText: "Call Johan today 14:30",
            now: now,
            locale: locale,
            timeZone: timeZone
        )

        XCTAssertEqual(result.title, "Call Johan")
        XCTAssertNotNil(result.dueDate)

        let dueComponents = calendar.dateComponents(in: timeZone, from: result.dueDate!)
        XCTAssertEqual(dueComponents.day, 23)
        XCTAssertEqual(dueComponents.hour, 14)
        XCTAssertEqual(dueComponents.minute, 30)
    }

    func testNonDateNumbersStayInTitle() {
        let result = LocalTaskParsingService.parseImmediate(
            rawText: "Fix iOS 18 bug",
            now: .now,
            locale: Locale(identifier: "en_US"),
            timeZone: .current
        )

        XCTAssertEqual(result.title, "Fix iOS 18 bug")
        XCTAssertNil(result.dueDate)
    }

    func testBareTailNumberWithoutDateKeywordDoesNotBecomeTime() {
        let result = LocalTaskParsingService.parseImmediate(
            rawText: "buy milk 5",
            now: .now,
            locale: Locale(identifier: "en_US"),
            timeZone: .current
        )

        XCTAssertEqual(result.title, "buy milk 5")
        XCTAssertNil(result.dueDate)
    }

    func testRelativeDateKeepsFirstMarker() throws {
        let timeZone = TimeZone(identifier: "Europe/Stockholm")!
        let locale = Locale(identifier: "sv_SE")
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 23, hour: 9))!

        let result = LocalTaskParsingService.parseImmediate(
            rawText: "påminn mig imorgon idag 18",
            now: now,
            locale: locale,
            timeZone: timeZone
        )

        let dueDate = try XCTUnwrap(result.dueDate)
        let dueComponents = calendar.dateComponents(in: timeZone, from: dueDate)
        XCTAssertEqual(dueComponents.day, 24)
        XCTAssertEqual(dueComponents.hour, 18)
    }

    func testCompoundBeforeReferenceWinsForIFoervaeg() throws {
        let timeZone = TimeZone(identifier: "Europe/Stockholm")!
        let locale = Locale(identifier: "sv_SE")
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 23, hour: 9))!

        let intents = CompoundIntentParser.parse(
            text: "träffa Johan imorgon 13 och maila honom i förväg",
            now: now,
            locale: locale,
            timeZone: timeZone
        )

        XCTAssertEqual(intents.count, 2)
        let emailDate = try XCTUnwrap(intents.last?.date)
        let emailComponents = calendar.dateComponents(in: timeZone, from: emailDate)
        XCTAssertEqual(emailComponents.day, 24)
        XCTAssertEqual(emailComponents.hour, 12)
        XCTAssertEqual(emailComponents.minute, 45)
        XCTAssertEqual(intents.last?.title, "maila honom")
    }

    func testOrdinaryAndTitleDoesNotSplitIntoMultipleIntents() {
        let intents = CompoundIntentParser.parse(
            text: "Lunch with Sarah and Tom tomorrow",
            now: .now,
            locale: Locale(identifier: "en_US"),
            timeZone: .current
        )

        XCTAssertEqual(intents.count, 1)
        XCTAssertEqual(intents.first?.type, .event)
        XCTAssertEqual(intents.first?.title, "Lunch with Sarah and Tom")
    }

    func testCompoundEmailSegmentStillSplitsWhenSecondClauseStartsWithVerb() {
        let intents = CompoundIntentParser.parse(
            text: "träffa Johan imorgon 13 och maila honom presentationen innan",
            now: .now,
            locale: Locale(identifier: "sv_SE"),
            timeZone: .current
        )

        XCTAssertEqual(intents.count, 2)
        XCTAssertEqual(intents.last?.type, .email)
    }

    // MARK: - hasTime flag (B-036)

    /// A date keyword + specific time-of-day must set `hasTime` so auto-classification can
    /// treat it as an appointment.
    func testHasTimeTrueWhenSpecificTimeStated() {
        let timeZone = TimeZone(identifier: "Europe/Stockholm")!
        let locale = Locale(identifier: "en_US")
        let calendar = Calendar(identifier: .gregorian)
        // 2026-03-23 is a Monday; "Tuesday" resolves to the next day.
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 23, hour: 9, minute: 0))!

        let result = LocalTaskParsingService.parseImmediate(
            rawText: "Dentist Tuesday 2pm",
            now: now,
            locale: locale,
            timeZone: timeZone
        )

        XCTAssertNotNil(result.dueDate)
        XCTAssertTrue(result.hasTime, "A stated time-of-day should mark hasTime = true")
        let due = calendar.dateComponents(in: timeZone, from: result.dueDate!)
        XCTAssertEqual(due.hour, 14)
    }

    /// A bare day with no time-of-day must leave `hasTime` false (deadline, not appointment).
    func testHasTimeFalseForDateOnly() {
        let timeZone = TimeZone(identifier: "Europe/Stockholm")!
        let locale = Locale(identifier: "en_US")
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 23, hour: 9, minute: 0))!

        let result = LocalTaskParsingService.parseImmediate(
            rawText: "Pay rent Friday",
            now: now,
            locale: locale,
            timeZone: timeZone
        )

        XCTAssertNotNil(result.dueDate, "A weekday keyword should still produce a (date-only) dueDate")
        XCTAssertFalse(result.hasTime, "A bare day with no time should leave hasTime = false")
    }

    /// No date and no time → no dueDate, hasTime false.
    func testHasTimeFalseWhenNothingParsed() {
        let result = LocalTaskParsingService.parseImmediate(
            rawText: "Buy groceries",
            now: .now,
            locale: Locale(identifier: "en_US"),
            timeZone: .current
        )
        XCTAssertNil(result.dueDate)
        XCTAssertFalse(result.hasTime)
    }
}
