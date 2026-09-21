import XCTest

/// Drives the real keyboard extension inside the container app's scratch
/// field. Requires the Scryboard keyboard to be enabled on the simulator:
///
///   xcrun simctl spawn <udid> defaults write com.apple.Preferences \
///     AppleKeyboards -array "com.fedg.scryboard.keyboard" "en_US@sw=QWERTY;hw=Automatic"
///
/// Screenshots are attached at each step so a failure can be seen, not guessed.
@MainActor
final class KeyboardSmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func dumpTree(_ name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Dismiss the system keyboard's first-run tip and switch to Scryboard.
    private func switchToScryboard() {
        let field = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "scratch field missing:\n\(app.debugDescription)")
        field.tap()

        let tip = app.buttons["Continue"]
        if tip.waitForExistence(timeout: 2) { tip.tap() }

        // The system keyboard's globe cycles to the next enabled keyboard.
        let globe = app.keyboards.buttons["Next keyboard"]
        if globe.waitForExistence(timeout: 3) {
            globe.tap()
        }
        snap("after-globe")
        dumpTree("tree-after-globe")
    }

    func testGridModeThenTypingModeThenSearch() {
        switchToScryboard()

        let bar = app.otherElements["Search cards"].firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "search-bar pill should be on screen in browsing mode")
        bar.tap()
        snap("typing-mode")

        for letter in ["l", "i", "g", "h", "t"] {
            app.buttons[letter].firstMatch.tap()
        }
        sleep(2)
        snap("suggestions")
        dumpTree("tree-suggestions")

        app.buttons["Search"].firstMatch.tap()
        sleep(4)
        snap("results")
        dumpTree("tree-results")
    }
}
