import Foundation
import Testing
@testable import ScryboardKit

/// Milestone 7's printing picker. Commander players care which art they send,
/// so the whole print run has to be reachable from any one card.
@Suite("Printing selection")
struct PrintingsTests {
    @Test("Search sends Scryfall's uniqueness, order and direction")
    func searchOptionsAreSent() async throws {
        let log = RequestLog()
        let client = ScryfallClient(transport: StubTransport(log: log, fixture: "search_page"))

        _ = try await client.search("t:goblin")
        let defaults = try #require(await log.last)
        #expect(defaults.queryValue("unique") == "cards")
        #expect(defaults.queryValue("order") == "name")
        #expect(defaults.queryValue("dir") == "auto")

        _ = try await client.search("t:goblin", unique: .art, order: .artist, direction: .ascending)
        let custom = try #require(await log.last)
        #expect(custom.queryValue("unique") == "art")
        #expect(custom.queryValue("order") == "artist")
        #expect(custom.queryValue("dir") == "asc")
    }

    @Test("Printings are matched on oracle_id, newest first")
    func printingsUseOracleID() async throws {
        let log = RequestLog()
        let client = ScryfallClient(transport: StubTransport(log: log, fixture: "search_printings"))
        let card = try Fixture.decode(Card.self, from: "card_normal")

        let printings = try await client.printings(of: card)
        let request = try #require(await log.last)

        #expect(request.url?.path == "/cards/search")
        #expect(request.queryValue("q") == "oracleid:4457ed35-7c10-48c8-9776-456485fdf070")
        #expect(request.queryValue("unique") == "prints")
        #expect(request.queryValue("order") == "released")
        #expect(request.queryValue("dir") == "desc")

        #expect(printings.data.count == 3)
        #expect(printings.data.map(\.setCode) == ["clb", "2xm", "lea"])
        // Every printing is a distinct image the user can pick between.
        #expect(Set(printings.data.compactMap { $0.imageURL(.normal) }).count == 3)
        #expect(Set(printings.data.map(\.oracleID)).count == 1)
    }

    /// `oracle_id` is absent from some card objects — tokens, and the faces of
    /// reversible cards. Falling back to the exact-name operator keeps the
    /// picker working instead of silently returning nothing.
    @Test("Printings fall back to an exact name match without an oracle_id")
    func printingsFallBackToName() async throws {
        let log = RequestLog()
        let client = ScryfallClient(transport: StubTransport(log: log, fixture: "search_printings"))
        let card = Card(
            id: UUID(uuidString: "77c6fa74-5543-42ac-9ead-0e890b188e99")!,
            name: "Lightning Bolt",
            setCode: "lea",
            collectorNumber: "161"
        )

        _ = try await client.printings(of: card)
        #expect(await log.last?.queryValue("q") == "!\"Lightning Bolt\"")
    }

    @Test("A double-faced card's printings query uses its full name")
    func printingsForDoubleFacedCard() throws {
        let card = try Fixture.decode(Card.self, from: "card_double_faced")
        let withoutOracleID = Card(
            id: card.id,
            name: card.name,
            layout: card.layout,
            setCode: card.setCode,
            collectorNumber: card.collectorNumber,
            cardFaces: card.cardFaces
        )

        #expect(
            ScryfallClient.printingsQuery(for: withoutOracleID)
                == "!\"Delver of Secrets // Insectile Aberration\""
        )
        #expect(ScryfallClient.printingsQuery(for: card) == "oracleid:\(card.oracleID!.uuidString.lowercased())")
    }
}
