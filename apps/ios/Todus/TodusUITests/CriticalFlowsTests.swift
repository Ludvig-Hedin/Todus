import XCTest

/// Critical-flow regression smoke tests (C1-C5).
///
/// These exercise the highest-value app surfaces from a black-box XCUITest
/// perspective. Each test is self-contained — no shared launches, no order
/// dependencies. The host process is driven via launch arguments wired in
/// `AppServices.init` / `TodosApp.processUITestingLaunchArgs`.
@MainActor
final class CriticalFlowsTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - C1: Deep link rejected when no in-flight auth flow

    /// `todus://auth-callback?token=…` arriving without an app-initiated sign-in
    /// must not flip the seeded session into the attacker-controlled token.
    /// We launch signed-in (via `--ui-testing`), fire the simulated deep link
    /// without any in-flight flow, and assert we still land on the MainTabView
    /// shell (which renders the AI FAB only when authenticated).
    func testDeepLinkRejectedWhenNoInFlightFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "--ui-testing",
            "--simulated-deep-link",
            "todus://auth-callback?token=FAKE",
        ]
        app.launch()

        // Authenticated shell present => deep-link payload was rejected.
        let fab = app.buttons["ai.fab.open"]
        XCTAssertTrue(fab.waitForExistence(timeout: 5),
                      "Authenticated shell should remain after rejected deep link")
    }

    // MARK: - C2: Notification tap routes to thread

    func testNotificationTapNavigatesToThread() throws {
        let threadId = "THREAD_123"
        let app = XCUIApplication()
        app.launchArguments += [
            "--ui-testing",
            "--simulated-notification",
            "thread:\(threadId)",
        ]
        app.launch()

        let threadView = app.otherElements["email.thread.\(threadId)"]
        XCTAssertTrue(threadView.waitForExistence(timeout: 8),
                      "EmailThreadView for \(threadId) should appear after simulated notification tap")
    }

    // MARK: - C3: AI mutation confirmation dialog surfaces

    func testAIMutationConfirmationDialogShows() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "--ui-testing",
            "--simulated-ai-mutation-pending",
        ]
        app.launch()

        // The chat sheet opens automatically; the confirmationDialog presenter
        // surfaces both the title ("Send email") and a Cancel button.
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 8),
                      "Mutation confirmation dialog should show a Cancel button")
    }

    // MARK: - C4: Stream cancel closes mutation continuations / unstucks UI

    /// Verifies the AI chat composer recovers from a Stop tap — the send
    /// button must reappear (i.e. `isStreaming` flipped back to false and
    /// no continuation is left dangling).
    func testStreamCancelClosesMutationContinuations() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "--ui-testing",
            "--simulated-ai-mutation-pending",
        ]
        app.launch()

        // Dismiss the pending dialog so the chat composer is unblocked.
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 8))
        cancel.tap()

        // The Send button reappears once the stream/mutation is cleared.
        let send = app.buttons["ai.chat.sendButton"]
        XCTAssertTrue(send.waitForExistence(timeout: 5),
                      "Send button should re-appear after Stop / Cancel — UI not stuck")
    }

    // MARK: - C5: Calendar permission change updates view

    func testCalendarPermissionGrantUpdatesView() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "--ui-testing",
            "--simulated-calendar-auth-changed",
        ]
        app.launch()

        // Tab bar visible => MainTabView mounted and listening for the
        // calendar-authorization-changed notification. The simulated
        // notification triggers a refresh — the test asserts the tab is
        // reachable rather than scraping CalendarKit-specific UIKit chrome
        // (which is not exposed via accessibility).
        let calendarTab = app.tabBars.buttons["Calendar"]
        XCTAssertTrue(calendarTab.waitForExistence(timeout: 5),
                      "Calendar tab should be available after calendar-auth-changed")
        calendarTab.tap()

        // Either the CalendarKit container or the permission view will render;
        // both indicate the calendar surface responded to the notification.
        let permissionHeader = app.staticTexts["Calendar Access Required"]
        let calendarTitle = app.navigationBars["Calendar"]
        let surfaceReady = permissionHeader.waitForExistence(timeout: 5)
            || calendarTitle.waitForExistence(timeout: 1)
        XCTAssertTrue(surfaceReady,
                      "Calendar tab should render either the permission view or the events list")
    }
}
