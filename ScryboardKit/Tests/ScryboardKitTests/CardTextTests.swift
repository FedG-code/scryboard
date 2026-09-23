import Foundation
import Testing
@testable import ScryboardKit

/// What "copy as text" puts on the pasteboard from the printings view.
@Suite("Card text")
struct CardTextTests {
    @Test("A printing is one Arena/Moxfield-style decklist line")
    func decklistLine() throws {
        let card = try Fixture.decode(Card.self, from: "card_normal")
        #expect(card.decklistLine == "Lightning Bolt (LEA) 161")
    }

    @Test("Multi-faced names keep Scryfall's double slash")
    func splitCardKeepsFullName() throws {
        let card = try Fixture.decode(Card.self, from: "card_split")
        #expect(card.decklistLine == "Fire // Ice (APC) 128")
    }

    @Test("The shared page link drops Scryfall's utm_source query")
    func pageLinkIsClean() throws {
        let tracked = try #require(URL(string: "https://scryfall.com/card/msc/806/lightning-bolt?utm_source=api"))
        let card = Card(id: UUID(), name: "Lightning Bolt", setCode: "msc", collectorNumber: "806", scryfallURI: tracked)
        #expect(card.pageURL?.absoluteString == "https://scryfall.com/card/msc/806/lightning-bolt")

        let plain = try Fixture.decode(Card.self, from: "card_normal")
        #expect(plain.pageURL == plain.scryfallURI)
        #expect(Card(id: UUID(), name: "X", setCode: "x", collectorNumber: "1").pageURL == nil)
    }

    @Test("Collector numbers are copied verbatim, suffix included")
    func collectorNumberSuffix() {
        let card = Card(id: UUID(), name: "Plains", setCode: "unf", collectorNumber: "235★")
        #expect(card.decklistLine == "Plains (UNF) 235★")
    }
}
