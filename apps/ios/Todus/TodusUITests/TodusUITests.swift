import XCTest

@MainActor
final class TodusUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()

        // Wait briefly for any window to appear (auth screen if not signed in
        // OR the tab bar if signed in).
        let predicate = NSPredicate(format: "exists == true")
        let windowExpectation = expectation(for: predicate, evaluatedWith: app.windows.firstMatch)
        wait(for: [windowExpectation], timeout: 10)

        XCTAssertTrue(app.windows.firstMatch.exists)
    }
}
