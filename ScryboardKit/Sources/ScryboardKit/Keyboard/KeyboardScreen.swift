import Foundation

/// Which pane the keyboard shows under the search bar, and how it gets from
/// one to the next: the builder, the results grid, or the QWERTY.
///
/// Pure data. The extension's controller feeds it every event that can
/// change what is on screen and draws whatever it says; the Kotlin IME will
/// do the same. Keeping the rules here means the sequences that used to
/// break the view layer (search, builder key, pill, return) are a test, not
/// a phone session. Extracted 2026-09-28 after exactly that sequence left
/// the keyboard with no pane at all.
public struct KeyboardScreen: Sendable, Hashable {
    public enum Pane: String, Sendable, Hashable, CaseIterable {
        /// The query builder: what an empty search bar shows.
        case builder
        /// Search results, or every printing of a held card.
        case grid
        /// The in-extension QWERTY, editing the pill.
        case keys
    }

    /// Everything that can move the keyboard between panes.
    public enum Event: Sendable, Hashable {
        /// The search-bar pill was tapped.
        case tapPill
        /// The QWERTY's builder key.
        case builderKey
        /// The return key, or the builder's Search. `hasQuery` is whether
        /// the pill holds anything to run.
        case submit(hasQuery: Bool)
        /// The pill's clear button.
        case clear
        /// The builder's Add. Card text and "Other…" hand off to the QWERTY
        /// so the rest can be typed.
        case addClause(handsOffToKeyboard: Bool)
        /// A card was held: its printings fill the grid.
        case holdCard(String)
        /// The floating Back over the printings. `hasQuery` is whether there
        /// is a grid to go back to (kept in memory or re-run from the pill).
        case back(hasQuery: Bool)
        /// The pipeline has nothing to show: the empty state.
        case nothingToShow
        /// A saved search came back after a keyboard rebuild.
        case restore(printings: String?)
        /// Full Access was granted or taken away.
        case fullAccess(Bool)
    }

    public private(set) var pane: Pane = .builder
    /// The held card whose printings fill the grid, if any.
    public private(set) var printings: String?
    public private(set) var hasFullAccess = true

    public init() {}

    /// What the extension draws. Without Full Access the builder gives way
    /// to the explainer, and the grid stays (empty) so its toolbar's globe
    /// is still there on systems that need one.
    public var visiblePane: Pane? {
        if hasFullAccess { return pane }
        return pane == .grid ? .grid : nil
    }

    /// The pill shows its caret while the QWERTY edits it.
    public var isEditing: Bool { pane == .keys }

    /// The floating Back capsule: only over printings.
    public var showsBack: Bool { hasFullAccess && pane == .grid && printings != nil }

    public mutating func apply(_ event: Event) {
        switch event {
        case .tapPill:
            // The pill is inert without Full Access.
            guard hasFullAccess else { return }
            pane = .keys
        case .builderKey:
            pane = .builder
        case .submit(let hasQuery):
            printings = nil
            pane = hasQuery ? .grid : .builder
        case .clear:
            // Clearing never changes what is under the bar, except from the
            // grid: an empty bar over results means a new search is coming.
            printings = nil
            if pane == .grid { pane = .keys }
        case .addClause(let handsOff):
            if handsOff { pane = .keys }
        case .holdCard(let name):
            printings = name
            pane = .grid
        case .back(let hasQuery):
            printings = nil
            pane = hasQuery ? .grid : .builder
        case .nothingToShow:
            pane = .builder
        case .restore(let printings):
            self.printings = printings
            pane = .grid
        case .fullAccess(let allowed):
            hasFullAccess = allowed
        }
        // The keys are never up without Full Access, whichever event asked
        // for them: there is nothing they could search.
        if !hasFullAccess, pane == .keys { pane = .grid }
    }

    /// The screen after a sequence of events, for tests and for reasoning.
    public func applying(_ events: [Event]) -> KeyboardScreen {
        var screen = self
        for event in events { screen.apply(event) }
        return screen
    }
}
