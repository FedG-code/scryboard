import Foundation

/// The query as the user edits it: the text plus where the caret sits.
///
/// A plain string could only grow at the end and lose its last character,
/// which meant a typo early in a query cost the whole query. This keeps a
/// caret so the pill can place it on tap and every edit happens there. Pure
/// data, offsets counted in `Character`s, so the Android IME ports it as is.
public struct QueryBuffer: Sendable, Hashable {
    public private(set) var text: String
    /// Where the next character goes, `0...text.count`.
    public private(set) var caret: Int

    /// Starts with the caret at the end, as a restored or cleared query does.
    public init(_ text: String = "") {
        self.text = text
        caret = text.count
    }

    public var isEmpty: Bool { text.isEmpty }

    public mutating func insert(_ string: String) {
        text.insert(contentsOf: string, at: index(caret))
        caret += string.count
    }

    /// Removes the character before the caret. Nothing to remove is not an error.
    public mutating func deleteBackward() {
        guard caret > 0 else { return }
        text.remove(at: index(caret - 1))
        caret -= 1
    }

    /// Adds a clause from the builder at the end, after a space when there is
    /// text already, and leaves the caret `caretFromEnd` characters before the
    /// end: inside the empty quotes of `o:""`, or at the end for anything else.
    public mutating func appendTerm(_ term: String, caretFromEnd: Int = 0) {
        if !text.isEmpty, text.last != " " { text.append(" ") }
        text.append(term)
        caret = max(0, text.count - caretFromEnd)
    }

    /// Places the caret, clamping an offset the text cannot hold.
    public mutating func moveCaret(to offset: Int) {
        caret = min(max(offset, 0), text.count)
    }

    private func index(_ offset: Int) -> String.Index {
        text.index(text.startIndex, offsetBy: offset)
    }
}
