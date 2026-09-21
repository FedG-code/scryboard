import XCTest

/// One-time simulator setup: walks the Settings app to add Scryboard as a
/// keyboard and grant Full Access. Run this before `KeyboardSmokeTests` on a
/// fresh simulator. Harmless to re-run: it stops when the keyboard is listed.
@MainActor
final class EnableKeyboardTests: XCTestCase {
    private let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Scrolls until an element with this label is on screen, then taps it.
    private func tapRow(_ label: String, exact: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = exact
            ? NSPredicate(format: "label == %@", label)
            : NSPredicate(format: "label BEGINSWITH %@", label)
        // Prefer a table cell: a page title can carry the same label as the row
        // that leads to it ("Keyboards").
        // A cell's label carries its value too ("Keyboards, 2"), so match by prefix.
        let cellPredicate = NSPredicate(format: "label BEGINSWITH %@", label)
        let cell = settings.cells.matching(cellPredicate).firstMatch
        let element = cell.exists ? cell : settings.descendants(matching: .any).matching(predicate).firstMatch
        for _ in 0..<8 where !(element.exists && element.isHittable) {
            settings.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 3), "no row labelled \(label)\n\(settings.debugDescription)", file: file, line: line)
        element.tap()
    }

    func testEnableScryboardKeyboard() {
        continueAfterFailure = false
        settings.launch()
        tapRow("General")
        tapRow("Keyboard")
        tapRow("Keyboards")
        snap("keyboards-list")

        if settings.staticTexts["Scryboard"].firstMatch.exists {
            snap("already-enabled")
        } else {
            tapRow("Add New Keyboard", exact: false)
            snap("add-keyboard")
            tapRow("Scryboard")
            snap("added")
        }

        // Full Access: Keyboards › Scryboard › Allow Full Access › Allow.
        // Re-query after the list settles; the row added a moment ago has no
        // frame yet from the automation's point of view.
        sleep(1)
        let row = settings.cells.staticTexts["Scryboard"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let toggle = settings.switches["Allow Full Access"].firstMatch
        if toggle.waitForExistence(timeout: 3), toggle.value as? String == "0" {
            toggle.tap()
            let allow = settings.alerts.buttons["Allow"].firstMatch
            if allow.waitForExistence(timeout: 3) { allow.tap() }
        }
        snap("full-access")
        XCTAssertEqual(toggle.value as? String, "1", "Full Access should be on")
    }
}
