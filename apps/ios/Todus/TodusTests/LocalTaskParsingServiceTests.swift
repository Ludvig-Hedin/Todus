import XCTest
@testable import MiniTaskApp

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
}
