import XCTest
import ScryboardKit

/// The real controller, real stack views, on a real window: after every
/// screen event, what the stacks show must be exactly what `KeyboardScreen`
/// says, and it must be drawn at full size at once. The Kit's own tests
/// prove the rules; this proves the views obey them, which is where the
/// 2026-09-28 bugs were: search, builder key, pill, return left every pane
/// hidden, and so did search then clear, both from animating `isHidden` on
/// a stack view's arranged subviews. The swap is now instant; if an
/// animation ever comes back, the drawn-height check here is what catches
/// a pane growing from nothing.
///
/// No network: events go straight to `apply(_:)`, never through a search.
/// Each step can spin the run loop for a while afterwards or not at all,
/// as a slow or a quick thumb would.
@MainActor
final class ScreenTransitionTests: XCTestCase {
    typealias Event = KeyboardScreen.Event
    typealias Pane = KeyboardScreen.Pane

    /// Every event the walks combine.
    private static let events: [Event] = [
        .tapPill, .builderKey, .submit(hasQuery: true), .submit(hasQuery: false), .clear,
        .addClause(handsOffToKeyboard: true), .addClause(handsOffToKeyboard: false),
        .holdCard("Avacyn, Angel of Hope"), .back(hasQuery: true), .back(hasQuery: false),
        .nothingToShow, .restore(printings: "Avacyn, Angel of Hope"),
    ]

    /// How long to spin the run loop after a step.
    private static let pacings: [TimeInterval] = [0, 0.05, 0.25]

    /// The window on screen: animations only run, and presentation layers
    /// only move, for views that are on screen. One at a time; the last one
    /// stays until the next controller replaces it.
    private var window: UIWindow?

    /// A controller on screen with Full Access, as on a phone once the
    /// switch is on; the test process itself has none.
    private func makeController() -> KeyboardViewController {
        let controller = KeyboardViewController()
        window?.isHidden = true
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 320))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        controller.loadViewIfNeeded()
        controller.view.layoutIfNeeded()
        controller.apply(.fullAccess(true))
        return controller
    }

    private func spin(_ seconds: TimeInterval) {
        guard seconds > 0 else { return }
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Drives one sequence and checks the views after every step.
    private func run(_ steps: [Event], settle: TimeInterval, on controller: KeyboardViewController,
                     file: StaticString = #filePath, line: UInt = #line) {
        var trail: [Event] = []
        for step in steps {
            trail.append(step)
            controller.apply(step)
            let expected = controller.screen.visiblePane.map { [$0] } ?? []
            let how = "after \(trail), settling \(settle) s"
            // What is on screen must be full size at once: a pane growing
            // from nothing leaves the column holding only the pill for a
            // frame, and the extension's self-sizing can lock that height
            // in. Presentation layers show what is drawn.
            if let pane = controller.screen.visiblePane {
                spin(0.03)
                let paneLayer = controller.paneView(pane).layer
                let drawn = (paneLayer.presentation() ?? paneLayer).bounds.height
                XCTAssertGreaterThanOrEqual(drawn, paneLayer.bounds.height - 1, "pane drawn short \(how)", file: file, line: line)
                XCTAssertGreaterThan(drawn, 100, "pane has no room \(how)", file: file, line: line)
                let column = controller.contentColumn.layer
                XCTAssertEqual((column.presentation() ?? column).bounds.height, column.bounds.height, accuracy: 1, "column drawn short \(how)", file: file, line: line)
            }
            spin(settle)
            XCTAssertEqual(controller.visiblePanes, expected, how, file: file, line: line)
            XCTAssertEqual(controller.backButton.isHidden, !controller.screen.showsBack, "Back \(how)", file: file, line: line)
            XCTAssertEqual(controller.searchBar.isEditing, controller.screen.isEditing, "caret \(how)", file: file, line: line)
        }
    }

    /// A named sequence at every pacing, on a fresh controller each time.
    private func runEveryWay(_ steps: [Event], file: StaticString = #filePath, line: UInt = #line) {
        for settle in Self.pacings {
            run(steps, settle: settle, on: makeController(), file: file, line: line)
        }
    }

    func testOpensOnTheBuilder() {
        let controller = makeController()
        XCTAssertEqual(controller.visiblePanes, [.builder])
        XCTAssertTrue(controller.backButton.isHidden)
    }

    /// Search "avacyn angel of horror", builder key, pill, return: the
    /// keyboard shrank to the pill with nothing under it (2026-09-28).
    func testSearchBuilderKeyPillReturn() {
        runEveryWay([.submit(hasQuery: true), .builderKey, .tapPill, .submit(hasQuery: true)])
    }

    /// Search "truth", then the pill's X: the same collapse (2026-09-28).
    func testSearchThenClear() {
        runEveryWay([.submit(hasQuery: true), .clear])
    }

    func testRoundTripsRepeat() {
        runEveryWay([.submit(hasQuery: true), .builderKey, .tapPill, .submit(hasQuery: true),
                     .builderKey, .tapPill, .submit(hasQuery: true), .clear, .submit(hasQuery: false),
                     .tapPill, .builderKey])
    }

    func testPrintingsAndBack() {
        runEveryWay([.submit(hasQuery: true), .holdCard("Shivan Dragon"), .back(hasQuery: true),
                     .holdCard("Shivan Dragon"), .tapPill, .builderKey, .submit(hasQuery: true),
                     .holdCard("Shivan Dragon"), .clear])
    }

    func testFullAccessLostAndRegained() {
        let controller = makeController()
        run([.submit(hasQuery: true), .holdCard("X"), .fullAccess(false), .tapPill, .fullAccess(true), .tapPill, .builderKey],
            settle: 0, on: controller)
        run([.tapPill, .fullAccess(false)], settle: 0.3, on: controller)
        XCTAssertEqual(controller.visiblePanes, [.grid])
    }

    /// Every pair of events, each on a fresh controller, left to settle.
    /// Longer sequences are the random walk's job; the Kit's own walk
    /// covers every sequence of four for the rules.
    func testEveryPair() {
        let pairs = Self.events.flatMap { a in Self.events.map { b in [a, b] } }
        for steps in pairs {
            run(steps, settle: 0.1, on: makeController())
        }
    }

    /// One controller, a long seeded walk of random events at random
    /// pacing: the sequences nobody thought to name.
    func testRandomWalk() {
        var seed: UInt64 = 0x5EED_2026_09_28
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(bound))
        }
        let controller = makeController()
        for _ in 0..<250 {
            let event = Self.events[next(Self.events.count)]
            let settle = Self.pacings[next(Self.pacings.count)]
            run([event], settle: settle, on: controller)
        }
    }

    func testHeightHoldsThroughTransitions() {
        let controller = makeController()
        let before = controller.contentColumn.bounds.height
        run([.submit(hasQuery: true), .builderKey, .tapPill, .submit(hasQuery: true), .clear],
            settle: 0.3, on: controller)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(controller.contentColumn.bounds.height, before)
    }
}
