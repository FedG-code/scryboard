import Foundation
import Testing
@testable import ScryboardKit

@Suite("Keyboard layout")
struct KeyboardLayoutTests {
    @Test("The letters plane is a QWERTY keyboard")
    func qwertyRows() {
        let layout = KeyboardLayout.standard(plane: .letters, shift: .off)

        #expect(layout.rows.count == 4)
        #expect(layout.rows[0].keys.map(\.label).joined() == "qwertyuiop")
        #expect(layout.rows[1].keys.map(\.label).joined() == "asdfghjkl")
        #expect(layout.rows[2].keys.map(\.action).first == .shift)
        #expect(layout.rows[2].keys.map(\.action).last == .backspace)
    }

    @Test("Shift redraws the letters in uppercase")
    func shiftedLabels() {
        for shift in [ShiftState.oneShot, .locked] {
            let layout = KeyboardLayout.standard(plane: .letters, shift: shift)
            #expect(layout.rows[0].keys.map(\.label).joined() == "QWERTYUIOP")
            // The action stays lowercase — casing is applied on insert, once.
            #expect(layout.rows[0].keys.first?.action == .character("q"))
        }
    }

    /// Apple requires the globe key in every keyboard extension, and a search
    /// bar the user cannot delete from is unusable.
    @Test("Every plane offers globe, delete and search")
    func requiredKeysArePresent() {
        for plane in KeyboardPlane.allCases {
            let actions = KeyboardLayout.standard(plane: plane, shift: .off).keys.map(\.action)
            #expect(actions.contains(.nextInputMode), "\(plane) is missing the globe key")
            #expect(actions.contains(.backspace), "\(plane) is missing delete")
            #expect(actions.contains(.search), "\(plane) is missing search")
            #expect(actions.contains(.space), "\(plane) is missing space")
        }
    }

    /// The point of the whole exercise: if a syntax character is not typeable,
    /// `classify(_:)` can never route to `/cards/search` and the query language
    /// is unreachable from the product.
    @Test("Every Scryfall syntax character is typeable")
    func syntaxCharactersAreReachable() {
        let reachable = KeyboardLayout.charactersReachable
        for character in QueryKind.syntaxCharacters {
            #expect(reachable.contains(character), "cannot type \(character)")
        }
    }

    @Test("The operators a real query needs are all reachable")
    func realQueriesAreTypeable() {
        let reachable = KeyboardLayout.charactersReachable
        for query in ["otag:removal", "cmc<=3", "pow>=4", "c=wu", "o:\"draw a card\"", "-is:reprint", "t:goblin r:mythic"] {
            let missing = Set(query).subtracting(reachable)
            #expect(missing.isEmpty, "\(query) needs \(missing.sorted())")
        }
    }

    @Test("Key identifiers are unique within a plane")
    func uniqueKeyIdentifiers() {
        for plane in KeyboardPlane.allCases {
            let ids = KeyboardLayout.standard(plane: plane, shift: .off).keys.map(\.id)
            #expect(Set(ids).count == ids.count, "\(plane) has duplicate key ids")
        }
    }

    @Test("Rows are within a key or so of each other in width")
    func rowWidthsAreBalanced() {
        for plane in KeyboardPlane.allCases {
            let widths = KeyboardLayout.standard(plane: plane, shift: .off).rows.map(\.widthUnits)
            let spread = (widths.max() ?? 0) - (widths.min() ?? 0)
            #expect(spread <= 1.0, "\(plane) rows vary by \(spread) key units: \(widths)")
        }
    }

    @Test("Only backspace repeats on hold")
    func onlyBackspaceRepeats() {
        for plane in KeyboardPlane.allCases {
            let repeating = KeyboardLayout.standard(plane: plane, shift: .off)
                .keys.filter(\.repeatsOnHold).map(\.action)
            #expect(repeating == [.backspace])
        }
    }
}

@Suite("Keyboard state")
struct KeyboardStateTests {
    @Test("A letter inserts itself")
    func insertsCharacter() {
        let transition = KeyboardState().applying(.character("q"))

        #expect(transition.effect == .insert("q"))
        #expect(transition.state == KeyboardState())
    }

    @Test("A one-shot shift capitalises exactly one character")
    func oneShotShift() {
        let armed = KeyboardState().applying(.shift)
        #expect(armed.state.shift == .oneShot)
        #expect(armed.effect == .none)

        let first = armed.state.applying(.character("j"))
        #expect(first.effect == .insert("J"))
        #expect(first.state.shift == .off)

        let second = first.state.applying(.character("a"))
        #expect(second.effect == .insert("a"))
    }

    @Test("A locked shift stays locked")
    func lockedShift() {
        var state = KeyboardState().lockingShift()
        #expect(state.shift == .locked)

        for character in ["j", "a", "c", "e"] {
            let transition = state.applying(.character(character))
            #expect(transition.effect == .insert(character.uppercased()))
            state = transition.state
        }
        #expect(state.shift == .locked)
    }

    @Test("Tapping shift again disarms it")
    func shiftCycles() {
        #expect(KeyboardState(shift: .off).applying(.shift).state.shift == .oneShot)
        #expect(KeyboardState(shift: .oneShot).applying(.shift).state.shift == .off)
        #expect(KeyboardState(shift: .locked).applying(.shift).state.shift == .off)
    }

    @Test("Space spends a one-shot shift and inserts a space")
    func spaceSpendsShift() {
        let transition = KeyboardState(shift: .oneShot).applying(.space)

        #expect(transition.effect == .insert(" "))
        #expect(transition.state.shift == .off)
    }

    /// iOS snaps back to letters after one symbol. Scryfall syntax chains them —
    /// `cmc<=3` is three symbol presses in a row — so this keyboard does not.
    @Test("The symbols plane does not snap back after one key")
    func symbolPlaneIsSticky() {
        var state = KeyboardState(plane: .symbols)

        for character in ["<", "=", "3"] {
            let transition = state.applying(.character(character))
            #expect(transition.effect == .insert(character))
            state = transition.state
        }
        #expect(state.plane == .symbols)
    }

    @Test("Switching plane clears an armed shift")
    func planeSwitchClearsShift() {
        let transition = KeyboardState(plane: .letters, shift: .oneShot).applying(.plane(.numbers))

        #expect(transition.state.plane == .numbers)
        #expect(transition.state.shift == .off)
        #expect(transition.effect == .none)
    }

    @Test("Delete, globe and search report themselves without changing state")
    func passthroughActions() {
        let state = KeyboardState(plane: .numbers, shift: .off)

        #expect(state.applying(.backspace).effect == .deleteBackward)
        #expect(state.applying(.nextInputMode).effect == .advanceToNextInputMode)
        #expect(state.applying(.search).effect == .submit)
        for action in [KeyAction.backspace, .nextInputMode, .search] {
            #expect(state.applying(action).state == state)
        }
    }

    @Test("Transitions are pure")
    func transitionsArePure() {
        let state = KeyboardState(plane: .letters, shift: .oneShot)
        #expect(state.applying(.character("q")) == state.applying(.character("q")))
        #expect(state.shift == .oneShot, "applying must not mutate the receiver")
    }

    /// The end-to-end shape of typing a query, entirely without a simulator.
    @Test("Typing a full query produces the right text")
    func typesAQuery() {
        var state = KeyboardState()
        var typed = ""

        func press(_ action: KeyAction) {
            let transition = state.applying(action)
            state = transition.state
            switch transition.effect {
            case .insert(let text): typed += text
            case .deleteBackward: typed.removeLast()
            default: break
            }
        }

        press(.shift)
        for character in "bolt" { press(.character(String(character))) }
        press(.space)
        press(.plane(.numbers))
        for character in "cmc" { press(.character(String(character))) }
        press(.plane(.symbols))
        press(.character("<"))
        press(.character("="))
        press(.plane(.numbers))
        press(.character("3"))
        press(.character("4"))
        press(.backspace)

        #expect(typed == "Bolt cmc<=3")
        #expect(state.applying(.search).effect == .submit)
        #expect(classify(typed) == .search)
    }
}
