import XCTest

/// The app against a dev den (EPEAKY_INVITE: an invite link to it, such as
/// http://localhost:4000/#invite=…, made by the den's host): the terms, the
/// den's page in the app, a chat, the den's Settings with Switch den.
final class EpeakyUITests: XCTestCase {
    func testOpenADenByInviteAndChat() throws {
        let invite = try XCTUnwrap(ProcessInfo.processInfo.environment["EPEAKY_INVITE"], "set TEST_RUNNER_EPEAKY_INVITE")
        let app = XCUIApplication()
        app.launchArguments = ["-reset"]
        // Notifications: allowed when iOS asks.
        addUIInterruptionMonitor(withDescription: "notifications") { alert in
            for b in ["Allow", "Allow While Using App", "OK"] where alert.buttons[b].exists { alert.buttons[b].tap(); return true }
            return false
        }
        app.launch()

        XCTAssertTrue(app.staticTexts["terms"].waitForExistence(timeout: 10), "the terms come first")
        shot(app, "1-start")
        let field = app.textFields["den-address"]
        field.tap()
        field.typeText(invite)
        app.buttons["open-typed"].tap()

        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 20))
        let chats = web.buttons["Chats"]
        XCTAssertTrue(chats.waitForExistence(timeout: 40), "in: the den's chat list")
        app.tap() // lets the interruption monitor answer the notification prompt
        shot(app, "2-chats")

        let general = web.buttons.matching(NSPredicate(format: "label BEGINSWITH 'General'")).firstMatch
        XCTAssertTrue(general.waitForExistence(timeout: 20))
        general.tap()
        let say = web.textViews.firstMatch
        XCTAssertTrue(say.waitForExistence(timeout: 10))
        say.tap()
        let words = "Hello from the iPhone app \(Int.random(in: 1000...9999))"
        say.typeText(words)
        web.buttons["Send"].tap()
        XCTAssertTrue(web.staticTexts[words].waitForExistence(timeout: 15), "the words are sent and shown")
        shot(app, "3-chat")

        // In a chat, "Chats" is its back button.
        web.buttons["Chats"].firstMatch.tap()
        let settings = web.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(web.buttons["Switch den"].waitForExistence(timeout: 10), "the app's own Switch den, in the den's Settings")
        XCTAssertTrue(web.buttons["Delete account"].exists)
        XCTAssertFalse(web.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Add to Home Screen'")).firstMatch.exists, "no home-screen hint in the app")
        shot(app, "4-settings")
        web.buttons["Switch den"].tap()
        XCTAssertTrue(app.buttons["open-default"].waitForExistence(timeout: 10), "back to the start, to open another den")
        XCTAssertTrue(app.staticTexts["Your dens"].exists)
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
