import XCTest
@testable import Todus

/// Tests for the "This weekend" snooze contract. (B-033.)
/// "Weekend" means the nearest upcoming Saturday OR Sunday still in the future, at 9am.
final class SnoozeOptionTests: XCTestCase {

    private func calendar(_ tz: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal
    }

    /// Saturday afternoon → should land on the imminent Sunday 9am, NOT next Saturday.
    func testSaturdayAfternoonSnoozesToSunday() {
        let tz = TimeZone(identifier: "Europe/Stockholm")!
        let cal = calendar(tz)
        // 2026-03-21 is a Saturday.
        let now = cal.date(from: DateComponents(year: 2026, month: 3, day: 21, hour: 15, minute: 0))!

        let result = SnoozeOption.weekend.date(now: now, calendar: cal)
        let comps = cal.dateComponents(in: tz, from: result)

        XCTAssertEqual(comps.weekday, 1, "Sunday")           // Sunday = 1
        XCTAssertEqual(comps.day, 22, "the very next day")
        XCTAssertEqual(comps.hour, 9)
        XCTAssertEqual(comps.minute, 0)
    }

    /// Saturday morning before 9am → still this Saturday 9am.
    func testSaturdayMorningStaysSaturday() {
        let tz = TimeZone(identifier: "Europe/Stockholm")!
        let cal = calendar(tz)
        let now = cal.date(from: DateComponents(year: 2026, month: 3, day: 21, hour: 7, minute: 0))!

        let result = SnoozeOption.weekend.date(now: now, calendar: cal)
        let comps = cal.dateComponents(in: tz, from: result)

        XCTAssertEqual(comps.weekday, 7, "Saturday")
        XCTAssertEqual(comps.day, 21)
        XCTAssertEqual(comps.hour, 9)
    }

    /// Sunday before 9am → keep this Sunday 9am.
    func testSundayBeforeNineStaysSunday() {
        let tz = TimeZone(identifier: "Europe/Stockholm")!
        let cal = calendar(tz)
        // 2026-03-22 is a Sunday.
        let now = cal.date(from: DateComponents(year: 2026, month: 3, day: 22, hour: 7, minute: 0))!

        let result = SnoozeOption.weekend.date(now: now, calendar: cal)
        let comps = cal.dateComponents(in: tz, from: result)

        XCTAssertEqual(comps.weekday, 1, "Sunday")
        XCTAssertEqual(comps.day, 22)
        XCTAssertEqual(comps.hour, 9)
    }

    /// Sunday after 9am → roll to NEXT Saturday 9am (both this-week candidates passed).
    func testSundayAfternoonRollsToNextSaturday() {
        let tz = TimeZone(identifier: "Europe/Stockholm")!
        let cal = calendar(tz)
        let now = cal.date(from: DateComponents(year: 2026, month: 3, day: 22, hour: 15, minute: 0))!

        let result = SnoozeOption.weekend.date(now: now, calendar: cal)
        let comps = cal.dateComponents(in: tz, from: result)

        XCTAssertEqual(comps.weekday, 7, "Saturday")
        XCTAssertEqual(comps.day, 28, "next Saturday")
        XCTAssertEqual(comps.hour, 9)
    }

    /// Mid-week (Wednesday) → nearest upcoming weekend day is Saturday.
    func testMidweekPicksUpcomingSaturday() {
        let tz = TimeZone(identifier: "Europe/Stockholm")!
        let cal = calendar(tz)
        // 2026-03-18 is a Wednesday.
        let now = cal.date(from: DateComponents(year: 2026, month: 3, day: 18, hour: 10, minute: 0))!

        let result = SnoozeOption.weekend.date(now: now, calendar: cal)
        let comps = cal.dateComponents(in: tz, from: result)

        XCTAssertEqual(comps.weekday, 7, "Saturday")
        XCTAssertEqual(comps.day, 21)
        XCTAssertEqual(comps.hour, 9)
        XCTAssertGreaterThan(result, now)
    }
}
