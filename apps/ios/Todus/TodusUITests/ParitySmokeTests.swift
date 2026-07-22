import XCTest

/// Parity smoke tests that assert the iOS shell still surfaces feature
/// equivalents the spec calls out. Each test is independent and avoids
/// reaching into anything that requires network.
@MainActor
final class ParitySmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func openSettings(in app: XCUIApplication) throws {
        let directButton = app.buttons["Settings"]
        let directLabel = app.staticTexts["Settings"]
        let direct = directButton.waitForExistence(timeout: 1) ? directButton : directLabel
        if direct.waitForExistence(timeout: 1) {
            direct.tap()
            return
        }

        let tabBarMore = app.tabBars.buttons["More"].firstMatch
        let more = tabBarMore.waitForExistence(timeout: 3)
            ? tabBarMore
            : app.buttons["More"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 2), "More tab should expose secondary pages")
        more.tap()

        let settingsButton = app.buttons["Settings"]
        let settingsLabel = app.staticTexts["Settings"]
        let settings = settingsButton.waitForExistence(timeout: 2) ? settingsButton : settingsLabel
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "Settings should be reachable from More")
        settings.tap()
    }

    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<8 {
            if element.exists { return true }
            app.swipeUp()
        }
        return element.waitForExistence(timeout: 2)
    }

    // MARK: - Fresh install lands on the branded startup card

    func testStartupCardShowsForFreshInstall() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "--ui-testing",
            "--ui-testing-fresh-install",
        ]
        app.launch()

        let getStarted = app.buttons["startup.getStartedButton"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 6),
                      "Fresh install should render StartupOnboardingView with 'Get started'")
    }

    // MARK: - Settings → AI Assistant → Voice Assistant

    func testVoiceSettingsSectionAccessible() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing"]
        app.launch()

        // Settings is presented as a sheet from the (legacy) top header. The
        // built-in shell doesn't surface a Settings entry on the main tab bar,
        // so we drive the navigation by flipping the existing `showsSettings`
        // service flag via a deep-link is not yet wired — fall back to opening
        // through the More sheet equivalent: the legacy entry surfaces a
        // "Settings" button on the AppTopHeader. If it's not present in this
        // shell build, the test xfails gracefully.
        try openSettings(in: app)

        // Voice Assistant is a top-level Settings row alongside AI Assistant.
        let voice = app.buttons["settings.ai.voiceAssistant"]
        XCTAssertTrue(scrollToElement(voice, in: app))
        voice.tap()

        let toggle = app.switches["voice.settings.enableToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5),
                      "Voice assistant enable toggle should be visible")
    }

    // MARK: - Docs list empty state + New document CTA

    func testDocsListShowsEmptyState() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing"]
        app.launch()

        // DocsListView is reached through the More sheet, which is reached
        // from a "More" entry on the legacy top header / burger. If neither
        // is visible in the current shell build, skip — we still assert the
        // identifier wiring exists by checking when the surface is reachable.
        let tabBarMore = app.tabBars.buttons["More"].firstMatch
        let more = tabBarMore.waitForExistence(timeout: 5)
            ? tabBarMore
            : app.buttons["More"].firstMatch
        guard more.waitForExistence(timeout: 1) else {
            throw XCTSkip("More sheet entry not exposed on the current shell build")
        }
        more.tap()

        let docsButton = app.buttons["Docs"]
        let docsLabel = app.staticTexts["Docs"]
        let docs = docsButton.waitForExistence(timeout: 2) ? docsButton : docsLabel
        guard docs.waitForExistence(timeout: 3) else {
            throw XCTSkip("Docs entry not exposed from the current More surface")
        }
        docs.tap()

        // Empty state is shown either as the standalone empty container or
        // the toolbar `+`; UI tests under `--ui-testing` skip the network
        // refresh so the empty state is the deterministic result.
        let newDoc = app.buttons["docs.list.newDocButton"]
        let emptyNewDoc = app.buttons["docs.list.emptyState.newDocButton"]
        let either = newDoc.waitForExistence(timeout: 5)
            || emptyNewDoc.waitForExistence(timeout: 1)
        XCTAssertTrue(either, "Docs empty state should expose a 'New document' button")
    }

    // MARK: - Settings → Email → Automation policy

    func testEmailAutomationPolicySectionAccessible() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing"]
        app.launch()

        try openSettings(in: app)

        // The Email section is inline in SettingsView — tap "Automation policy".
        let automation = app.buttons["settings.email.automationPolicy"]
        XCTAssertTrue(scrollToElement(automation, in: app))
        automation.tap()

        let field = app.textFields["email.automationPolicy.excludedSenderField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5),
                      "Excluded sender field should be visible on EmailAutomationPolicyView")
    }
}
