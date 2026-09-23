import Foundation

/// Which set of keys is on screen.
///
/// A keyboard extension cannot summon the system keyboard for its own text
/// field, so Scryboard draws its own. Three planes is the iOS convention and
/// enough to reach every character Scryfall's query language uses.
public enum KeyboardPlane: String, Sendable, Hashable, CaseIterable {
    case letters
    case numbers
    case symbols
}

/// Shift is a three-state affair on iOS: off, armed for one character, or locked.
public enum ShiftState: String, Sendable, Hashable, CaseIterable {
    case off
    /// Armed for exactly one character, then falls back to ``off``.
    case oneShot
    case locked

    public var isUppercase: Bool { self != .off }
}

/// What pressing a key means. Deliberately a value, not a closure: the UI layer
/// renders keys and reports taps, and every decision lives in ``KeyboardState``.
public enum KeyAction: Sendable, Hashable {
    /// Insert this key's character. The string is the *unshifted* form; shift is
    /// applied by ``KeyboardState/applying(_:)``.
    case character(String)
    case space
    case backspace
    case shift
    case plane(KeyboardPlane)
    /// The globe key. Apple requires a keyboard extension to offer it.
    case nextInputMode
    /// Commit the search bar's contents.
    case search
    /// Back to the query builder, keeping what is in the search bar.
    case builder
}

public struct KeyboardKey: Sendable, Hashable, Identifiable {
    public let id: String
    public let action: KeyAction
    /// What to draw on the keycap, already shifted where that applies.
    public let label: String
    /// Width relative to a letter key, which is `1`. The renderer turns these
    /// into points; keeping it relative is what makes one layout fit every
    /// device width.
    public let widthUnits: Double
    /// Holding the key repeats it. Backspace only.
    public let repeatsOnHold: Bool

    public init(
        id: String,
        action: KeyAction,
        label: String,
        widthUnits: Double = 1,
        repeatsOnHold: Bool = false
    ) {
        self.id = id
        self.action = action
        self.label = label
        self.widthUnits = widthUnits
        self.repeatsOnHold = repeatsOnHold
    }
}

public struct KeyboardRow: Sendable, Hashable {
    public let keys: [KeyboardKey]

    public init(_ keys: [KeyboardKey]) {
        self.keys = keys
    }

    /// Total width of the row in key units, for the renderer's arithmetic.
    public var widthUnits: Double {
        keys.reduce(0) { $0 + $1.widthUnits }
    }
}

/// A full set of rows, derived from a plane and a shift state.
///
/// Pure data with no UIKit anywhere near it: the extension renders this, and the
/// Kotlin IME will render the same structure.
public struct KeyboardLayout: Sendable, Hashable {
    public let rows: [KeyboardRow]

    public init(rows: [KeyboardRow]) {
        self.rows = rows
    }

    public var keys: [KeyboardKey] {
        rows.flatMap(\.keys)
    }

    /// Every character this layout can produce, across all planes, is what
    /// ``charactersReachable`` answers for — see the tests: the syntax
    /// characters ``classify(_:)`` keys off must all be typeable, or a user
    /// cannot write `otag:removal` at all.
    public var characters: Set<Character> {
        var result: Set<Character> = []
        for key in keys {
            if case .character(let text) = key.action {
                result.formUnion(text)
            }
            if case .space = key.action {
                result.insert(" ")
            }
        }
        return result
    }

    // MARK: - The Scryboard keyboard

    public static func standard(plane: KeyboardPlane, shift: ShiftState) -> KeyboardLayout {
        switch plane {
        case .letters: letters(shift: shift)
        case .numbers: numbers()
        case .symbols: symbols()
        }
    }

    /// Characters reachable from any plane. Useful to assert against, and to
    /// answer "can the user actually type this query?".
    public static var charactersReachable: Set<Character> {
        KeyboardPlane.allCases.reduce(into: Set<Character>()) { result, plane in
            result.formUnion(standard(plane: plane, shift: .off).characters)
            result.formUnion(standard(plane: plane, shift: .locked).characters)
        }
    }

    private static func letters(shift: ShiftState) -> KeyboardLayout {
        KeyboardLayout(rows: [
            // The query-syntax row, above the letters like the number row on
            // an iPad: every operator a typical search needs without leaving
            // the plane. `:` opens every filter, so it sits in the middle,
            // half a key wider, with `<` and `>` either side; `"` quotes,
            // `!` is an exact name, `-` negates, `()` group, `/` splits
            // faces. The row is the width of the letter row below it.
            syntaxRow,
            KeyboardRow(characterKeys("qwertyuiop", shift: shift)),
            KeyboardRow(characterKeys("asdfghjkl", shift: shift)),
            KeyboardRow(
                [shiftKey(shift)] + characterKeys("zxcvbnm", shift: shift) + [backspaceKey]
            ),
            bottomRow(planeKey: .numbers, label: "123"),
        ])
    }

    private static func numbers() -> KeyboardLayout {
        KeyboardLayout(rows: [
            KeyboardRow(characterKeys("1234567890", shift: .off)),
            // The Scryfall-shaped row: `:` opens every filter, `-` negates,
            // `"` quotes a phrase, `/` separates the faces of a split card.
            KeyboardRow(characterKeys("-/:;()&@\"", shift: .off)),
            KeyboardRow(
                [planeKey(.symbols, label: "#+=")]
                    + characterKeys(".,?!'", shift: .off, widthUnits: punctuationRowWidth)
                    + [backspaceKey]
            ),
            bottomRow(planeKey: .letters, label: "ABC"),
        ])
    }

    private static func symbols() -> KeyboardLayout {
        KeyboardLayout(rows: [
            KeyboardRow(characterKeys("[]{}#%^*+=", shift: .off)),
            // `<` and `>` complete the comparison operators: `cmc<=3`, `pow>4`.
            KeyboardRow(characterKeys("_\\|~<>$€£¥", shift: .off)),
            KeyboardRow(
                [planeKey(.numbers, label: "123")]
                    + characterKeys(".,?!'", shift: .off, widthUnits: punctuationRowWidth)
                    + [backspaceKey]
            ),
            bottomRow(planeKey: .letters, label: "ABC"),
        ])
    }

    // MARK: - Key construction

    private static var syntaxRow: KeyboardRow {
        let colonUnits = 1.5
        let others = "\"!-(<" + ">)=/"
        let otherUnits = (10 - colonUnits) / Double(others.count)
        return KeyboardRow(
            characterKeys("\"!-(<", shift: .off, widthUnits: otherUnits)
                + characterKeys(":", shift: .off, widthUnits: colonUnits)
                + characterKeys(">)=/", shift: .off, widthUnits: otherUnits)
        )
    }

    private static func characterKeys(
        _ characters: String,
        shift: ShiftState,
        widthUnits: Double = 1
    ) -> [KeyboardKey] {
        characters.map { character in
            let text = String(character)
            let label = shift.isUppercase ? text.uppercased() : text
            return KeyboardKey(
                id: "char-\(text)",
                action: .character(text),
                label: label,
                widthUnits: widthUnits
            )
        }
    }

    /// The punctuation row of the non-letter planes holds five keys where the
    /// letter planes hold seven, so each one takes the slack. Without it the row
    /// is two key units short and renders visibly narrower than the rest.
    private static let punctuationRowWidth = 1.4

    private static func shiftKey(_ shift: ShiftState) -> KeyboardKey {
        KeyboardKey(
            id: "shift",
            action: .shift,
            label: shift == .locked ? "⇪" : "⇧",
            widthUnits: 1.5
        )
    }

    private static let backspaceKey = KeyboardKey(
        id: "backspace",
        action: .backspace,
        label: "⌫",
        widthUnits: 1.5,
        repeatsOnHold: true
    )

    private static func planeKey(_ plane: KeyboardPlane, label: String) -> KeyboardKey {
        KeyboardKey(id: "plane-\(plane.rawValue)", action: .plane(plane), label: label, widthUnits: 1.5)
    }

    private static func bottomRow(planeKey plane: KeyboardPlane, label: String) -> KeyboardRow {
        KeyboardRow([
            KeyboardKey(id: "plane-\(plane.rawValue)", action: .plane(plane), label: label, widthUnits: 1.25),
            // The way back down to the query builder; the space bar paid
            // for it. Drawn like every other function key.
            KeyboardKey(id: "builder", action: .builder, label: "⊞", widthUnits: 1.25),
            // Required by Apple. Never omit it, never hide it behind a long press.
            KeyboardKey(id: "globe", action: .nextInputMode, label: "🌐", widthUnits: 1.25),
            // Unlabelled, as on the emoji keyboard: everyone knows the wide key.
            KeyboardKey(id: "space", action: .space, label: "", widthUnits: 3.75),
            KeyboardKey(id: "search", action: .search, label: "⏎", widthUnits: 2.5),
        ])
    }
}
