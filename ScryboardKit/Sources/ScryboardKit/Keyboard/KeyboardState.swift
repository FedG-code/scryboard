import Foundation

/// What the host should do as a result of a key press.
///
/// The state machine decides; the view controller performs. Keeping the two
/// apart is what makes the whole thing testable without a simulator, and what
/// the Android IME will reuse unchanged apart from ``advanceToNextInputMode``.
public enum KeyboardEffect: Sendable, Hashable {
    /// Nothing leaves the keyboard — the press only changed which keys are drawn.
    case none
    case insert(String)
    case deleteBackward
    /// The user asked to run the query as it stands.
    case submit
    /// Hand over to the next keyboard. The globe key.
    case advanceToNextInputMode
}

/// The result of a key press: where the keyboard ends up, and what the host
/// should do about it.
public struct KeyboardTransition: Sendable, Hashable {
    public let state: KeyboardState
    public let effect: KeyboardEffect

    public init(state: KeyboardState, effect: KeyboardEffect) {
        self.state = state
        self.effect = effect
    }
}

/// Which plane is showing and whether shift is armed.
///
/// A pure value with a pure transition function, so every rule below is a unit
/// test rather than something to discover on a device.
public struct KeyboardState: Sendable, Hashable {
    public var plane: KeyboardPlane
    public var shift: ShiftState

    public init(plane: KeyboardPlane = .letters, shift: ShiftState = .off) {
        self.plane = plane
        self.shift = shift
    }

    /// The keys to draw for this state.
    public var layout: KeyboardLayout {
        KeyboardLayout.standard(plane: plane, shift: shift)
    }

    /// The single rule set for what a key press does.
    public func applying(_ action: KeyAction) -> KeyboardTransition {
        var next = self

        switch action {
        case .character(let text):
            let inserted = shift.isUppercase ? text.uppercased() : text
            // A one-shot shift is spent on the character it capitalised;
            // a locked shift stays.
            if shift == .oneShot { next.shift = .off }
            // iOS returns to letters after a single punctuation press. Scryfall
            // syntax is the opposite: `cmc<=3` and `o:"draw a card"` chain
            // symbols, so the plane stays put until the user changes it.
            return KeyboardTransition(state: next, effect: .insert(inserted))

        case .space:
            if shift == .oneShot { next.shift = .off }
            return KeyboardTransition(state: next, effect: .insert(" "))

        case .backspace:
            return KeyboardTransition(state: next, effect: .deleteBackward)

        case .shift:
            next.shift = shift.tapped
            return KeyboardTransition(state: next, effect: .none)

        case .plane(let plane):
            next.plane = plane
            // Shift is a letters-plane concept; leaving it armed would surprise
            // the user on the way back.
            next.shift = .off
            return KeyboardTransition(state: next, effect: .none)

        case .nextInputMode:
            return KeyboardTransition(state: next, effect: .advanceToNextInputMode)

        case .search:
            return KeyboardTransition(state: next, effect: .submit)
        }
    }

    /// Double-tapping shift locks it. The UI owns the timing; this is what it
    /// calls once it has decided a double tap happened.
    public func lockingShift() -> KeyboardState {
        KeyboardState(plane: plane, shift: .locked)
    }
}

extension ShiftState {
    /// One tap cycles off → armed → off. Locking is a double tap, which only the
    /// UI can detect, so it is not part of this cycle.
    var tapped: ShiftState {
        switch self {
        case .off: .oneShot
        case .oneShot: .off
        case .locked: .off
        }
    }
}
