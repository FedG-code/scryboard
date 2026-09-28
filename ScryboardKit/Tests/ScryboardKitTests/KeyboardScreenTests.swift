import Foundation
import Testing
@testable import ScryboardKit

/// The keyboard's three panes and every way between them. The sequences a
/// phone session found are here by name; the walk at the end tries every
/// short sequence and checks what must always hold.
@Suite("Keyboard screen")
struct KeyboardScreenTests {
    typealias Event = KeyboardScreen.Event

    /// Every event the walk combines. `holdCard` and `restore` carry a name;
    /// one each is enough, the rules never read it.
    static let events: [Event] = [
        .tapPill, .builderKey, .submit(hasQuery: true), .submit(hasQuery: false), .clear,
        .addClause(handsOffToKeyboard: true), .addClause(handsOffToKeyboard: false),
        .holdCard("Avacyn, Angel of Hope"), .back(hasQuery: true), .back(hasQuery: false),
        .nothingToShow, .restore(printings: nil), .restore(printings: "Avacyn, Angel of Hope"),
        .fullAccess(false), .fullAccess(true),
    ]

    @Test("Opens on the builder, editing nothing, with no way back")
    func initial() {
        let screen = KeyboardScreen()
        #expect(screen.pane == .builder)
        #expect(screen.visiblePane == .builder)
        #expect(!screen.isEditing)
        #expect(!screen.showsBack)
        #expect(screen.printings == nil)
    }

    @Test("Search, builder key, pill, return ends on the grid (the 2026-09-28 sequence)")
    func searchBuilderPillReturn() {
        let steps: [Event] = [.submit(hasQuery: true), .builderKey, .tapPill, .submit(hasQuery: true)]
        var screen = KeyboardScreen()
        var seen: [KeyboardScreen.Pane] = []
        for step in steps {
            screen.apply(step)
            seen.append(screen.pane)
        }
        #expect(seen == [.grid, .builder, .keys, .grid])
        #expect(screen.visiblePane == .grid)
        #expect(!screen.isEditing)
    }

    @Test("The pill opens the keys from every pane; the builder key comes back")
    func pillAndBuilderKey() {
        for start in [KeyboardScreen(), KeyboardScreen().applying([.submit(hasQuery: true)]), KeyboardScreen().applying([.tapPill])] {
            let typing = start.applying([.tapPill])
            #expect(typing.pane == .keys)
            #expect(typing.isEditing)
            #expect(typing.applying([.builderKey]).pane == .builder)
        }
    }

    @Test("Return with an empty pill shows the builder, not an empty grid")
    func emptySubmit() {
        let screen = KeyboardScreen().applying([.tapPill, .submit(hasQuery: false)])
        #expect(screen.pane == .builder)
        #expect(!screen.isEditing)
    }

    @Test("Holding a card shows printings with Back; Back returns to the grid or the builder")
    func printings() {
        let held = KeyboardScreen().applying([.submit(hasQuery: true), .holdCard("Shivan Dragon")])
        #expect(held.pane == .grid)
        #expect(held.printings == "Shivan Dragon")
        #expect(held.showsBack)

        let backToGrid = held.applying([.back(hasQuery: true)])
        #expect(backToGrid.pane == .grid)
        #expect(backToGrid.printings == nil)
        #expect(!backToGrid.showsBack)

        let backToBuilder = held.applying([.back(hasQuery: false)])
        #expect(backToBuilder.pane == .builder)
        #expect(backToBuilder.printings == nil)
    }

    @Test("A new search or a clear forgets the printings")
    func printingsForgotten() {
        let held = KeyboardScreen().applying([.submit(hasQuery: true), .holdCard("Shivan Dragon")])
        #expect(held.applying([.tapPill, .submit(hasQuery: true)]).printings == nil)
        #expect(held.applying([.clear]).printings == nil)
    }

    @Test("Clear opens the keys from the grid and changes nothing elsewhere")
    func clear() {
        #expect(KeyboardScreen().applying([.submit(hasQuery: true), .clear]).pane == .keys)
        #expect(KeyboardScreen().applying([.clear]).pane == .builder)
        #expect(KeyboardScreen().applying([.tapPill, .clear]).pane == .keys)
    }

    @Test("Add stays on the builder unless the clause needs typing")
    func addClause() {
        #expect(KeyboardScreen().applying([.addClause(handsOffToKeyboard: false)]).pane == .builder)
        #expect(KeyboardScreen().applying([.addClause(handsOffToKeyboard: true)]).pane == .keys)
    }

    @Test("A restored search comes back on the grid, printings included")
    func restore() {
        let plain = KeyboardScreen().applying([.restore(printings: nil)])
        #expect(plain.pane == .grid)
        #expect(!plain.showsBack)
        let held = KeyboardScreen().applying([.restore(printings: "Shivan Dragon")])
        #expect(held.pane == .grid)
        #expect(held.showsBack)
    }

    @Test("Without Full Access the builder gives way, the keys close, and the pill is inert")
    func fullAccess() {
        let denied = KeyboardScreen().applying([.fullAccess(false)])
        #expect(denied.visiblePane == nil)
        #expect(denied.applying([.tapPill]).pane == .builder)
        #expect(KeyboardScreen().applying([.tapPill, .fullAccess(false)]).pane == .grid)
        let grid = KeyboardScreen().applying([.submit(hasQuery: true), .holdCard("X"), .fullAccess(false)])
        #expect(grid.visiblePane == .grid)
        #expect(!grid.showsBack)
        #expect(grid.applying([.fullAccess(true)]).showsBack)
    }

    @Test("Every sequence of up to four events keeps the invariants")
    func walk() {
        var count = 0
        func visit(_ screen: KeyboardScreen, _ path: [Event], depth: Int) {
            for event in Self.events {
                let next = screen.applying([event])
                let trail = path + [event]
                count += 1
                // One pane at most, and only ever none without Full Access.
                if next.visiblePane == nil {
                    #expect(!next.hasFullAccess, "no pane with Full Access after \(trail)")
                }
                #expect(next.isEditing == (next.pane == .keys), "editing off the keys after \(trail)")
                if next.showsBack {
                    #expect(next.pane == .grid && next.printings != nil && next.hasFullAccess, "Back off the printings after \(trail)")
                }
                if next.pane == .keys {
                    #expect(next.hasFullAccess, "keys without Full Access after \(trail)")
                }
                // The pill always opens the keys, and the builder key always
                // closes them, whatever came before.
                if next.hasFullAccess {
                    #expect(next.applying([.tapPill]).pane == .keys, "pill did nothing after \(trail)")
                }
                #expect(next.applying([.builderKey]).pane == .builder, "builder key did nothing after \(trail)")
                if depth > 1 { visit(next, trail, depth: depth - 1) }
            }
        }
        visit(KeyboardScreen(), [], depth: 4)
        #expect(count == Self.events.count + Self.events.count * Self.events.count
                + Self.events.count * Self.events.count * Self.events.count
                + Self.events.count * Self.events.count * Self.events.count * Self.events.count)
    }
}
