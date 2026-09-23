import Testing
@testable import ScryboardKit

@Suite("Query buffer")
struct QueryBufferTests {
    @Test("A new buffer puts the caret at the end")
    func startsAtEnd() {
        #expect(QueryBuffer().caret == 0)
        #expect(QueryBuffer("t:goblin").caret == 8)
        #expect(QueryBuffer().isEmpty)
    }

    @Test("Typing inserts at the caret and carries it along")
    func insertsAtCaret() {
        var buffer = QueryBuffer("lightning bolt")
        buffer.moveCaret(to: 9)
        buffer.insert(",")
        #expect(buffer.text == "lightning, bolt")
        #expect(buffer.caret == 10)

        buffer.insert(" or")
        #expect(buffer.text == "lightning, or bolt")
        #expect(buffer.caret == 13)
    }

    @Test("Backspace removes the character before the caret")
    func deletesBeforeCaret() {
        var buffer = QueryBuffer("goblun")
        buffer.moveCaret(to: 5)
        buffer.deleteBackward()
        #expect(buffer.text == "gobln")
        #expect(buffer.caret == 4)
        buffer.insert("i")
        #expect(buffer.text == "goblin")
        #expect(buffer.caret == 5)
    }

    @Test("Backspace at the start does nothing")
    func deleteAtStartIsHarmless() {
        var buffer = QueryBuffer("bolt")
        buffer.moveCaret(to: 0)
        buffer.deleteBackward()
        #expect(buffer.text == "bolt")
        #expect(buffer.caret == 0)

        var empty = QueryBuffer()
        empty.deleteBackward()
        #expect(empty == QueryBuffer())
    }

    @Test("The caret is clamped to the text")
    func caretClamps() {
        var buffer = QueryBuffer("bolt")
        buffer.moveCaret(to: 99)
        #expect(buffer.caret == 4)
        buffer.moveCaret(to: -3)
        #expect(buffer.caret == 0)
    }

    @Test("Offsets count characters, not code units")
    func countsCharacters() {
        var buffer = QueryBuffer("café")
        #expect(buffer.caret == 4)
        buffer.moveCaret(to: 3)
        buffer.deleteBackward()
        #expect(buffer.text == "caé")
    }

    @Test("A builder clause is appended after a space, caret at the end")
    func appendsTerms() {
        var buffer = QueryBuffer()
        buffer.appendTerm("id<=ub")
        #expect(buffer.text == "id<=ub")
        #expect(buffer.caret == 6)
        buffer.appendTerm("t:creature")
        #expect(buffer.text == "id<=ub t:creature")
        #expect(buffer.caret == buffer.text.count)
        // A trailing space the user typed is not doubled.
        buffer.insert(" ")
        buffer.appendTerm("r:mythic")
        #expect(buffer.text == "id<=ub t:creature r:mythic")
    }

    @Test("Card text leaves the caret between the quotes")
    func caretInsideQuotes() {
        var buffer = QueryBuffer("t:creature")
        buffer.appendTerm("o:\"\"", caretFromEnd: 1)
        #expect(buffer.text == "t:creature o:\"\"")
        #expect(buffer.caret == buffer.text.count - 1)
        buffer.insert("draw")
        #expect(buffer.text == "t:creature o:\"draw\"")
    }
}
