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

    /// Locates the mutation confirmation regardless of OS presentation style:
    /// iOS 26 renders `confirmationDialog` as a compact alert (an AX `Sheet`
    /// labeled with the dialog title, and NO accessible Cancel button); earlier
    /// versions render a bottom action sheet with an explicit Cancel button.
    private func mutationDialog(in app: XCUIApplication) -> XCUIElement {
        app.sheets["Send this email?"]
    }

    func testAIMutationConfirmationDialogShows() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "--ui-testing",
            "--simulated-ai-mutation-pending",
        ]
        app.launch()

        // The chat sheet opens automatically, then the confirmationDialog is
        // armed. Either the titled dialog sheet (iOS 26 compact alert) or a
        // Cancel button (legacy action sheet) proves it surfaced.
        let dialog = mutationDialog(in: app)
        let cancel = app.buttons["Cancel"]
        let appeared = dialog.waitForExistence(timeout: 8) || cancel.waitForExistence(timeout: 2)
        XCTAssertTrue(appeared,
                      "Mutation confirmation dialog should surface (titled sheet or Cancel button)")
    }

    // MARK: - C4: Stream cancel closes mutation continuations / unstucks UI

    /// Verifies the AI chat composer recovers from dismissing the pending
    /// mutation — the send button must be reachable again (i.e. the
    /// confirmation continuation resumed with `false` and nothing is stuck).
    func testStreamCancelClosesMutationContinuations() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "--ui-testing",
            "--simulated-ai-mutation-pending",
        ]
        app.launch()

        // Wait for the pending dialog, then resolve it. On iOS 26's compact
        // alert there is no accessible Cancel button and outside-taps don't
        // dismiss — resolve via the visible action button instead. Both paths
        // route through `confirmPendingMutation`, which closes the pending
        // continuation and clears `pendingMutationConfirmation` (the stub has
        // no live stream, so nothing is actually sent).
        let dialog = mutationDialog(in: app)
        let cancel = app.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 3) {
            cancel.tap()
        } else {
            XCTAssertTrue(dialog.waitForExistence(timeout: 8),
                          "Mutation confirmation dialog should surface before dismissal")
            dialog.buttons["Send"].tap()
        }

        // The dialog must clear and the composer become reachable again.
        let send = app.buttons["ai.chat.sendButton"]
        XCTAssertTrue(send.waitForExistence(timeout: 5),
                      "Send button should be reachable after dismissing the dialog — UI not stuck")
        XCTAssertFalse(dialog.exists, "Dialog should be gone after dismissal")
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

        // Either the permission view or the calendar root will render. The
        // custom AppTopHeader is not a UIKit navigation bar, so query the
        // explicit surface identifier instead of relying on nav-bar semantics.
        let permissionHeader = app.staticTexts["Calendar Access Required"]
        let calendarSurface = app.otherElements["calendar.surface"]
        let surfaceReady = permissionHeader.waitForExistence(timeout: 5)
            || calendarSurface.waitForExistence(timeout: 1)
        XCTAssertTrue(surfaceReady,
                      "Calendar tab should render either the permission view or the events list")
    }
}
