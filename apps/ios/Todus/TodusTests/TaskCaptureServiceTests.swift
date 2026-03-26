import XCTest
@testable import MiniTaskApp

final class TaskCaptureServiceTests: XCTestCase {
    func testSplitInputLinesCreatesOnlyNonEmptyEntries() {
        let lines = TaskCaptureService.splitInputLines(
            """
            Fix navbar bug

              Buy milk tomorrow
            Call Johan 14
            """
        )

        XCTAssertEqual(lines, [
            "Fix navbar bug",
            "Buy milk tomorrow",
            "Call Johan 14"
        ])
    }

    func testInstantTitleKeepsOriginalInput() {
        XCTAssertEqual(TaskCaptureService.instantTitle(from: "  Review QA checklist "), "Review QA checklist")
    }
}
