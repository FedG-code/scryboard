import Foundation
import Testing
@testable import ScryboardKit

/// A printing picked from the printings view becomes the one every later
/// grid shows for that card. The fixtures carry Lightning Bolt three times
/// (`search_printings`: clb, 2xm, lea) and once in a search (`search_page`:
/// lea, next to Swords to Plowshares).
@Suite("Preferred printings")
struct PreferredPrintingsTests {
    private func printings() throws -> [Card] {
        try Fixture.decode(SearchPage.self, from: "search_printings").data
    }

    private func searchResults() throws -> [Card] {
        try Fixture.decode(SearchPage.self, from: "search_page").data
    }

    @Test("Cards are keyed by oracle_id, or by name without one")
    func keys() throws {
        let bolts = try printings()
        #expect(Set(bolts.map(PreferredPrintings.key(for:))).count == 1)
        #expect(PreferredPrintings.key(for: bolts[0]) == "oracle:4457ed35-7c10-48c8-9776-456485fdf070")

        let token = Card(id: UUID(), name: "Goblin", setCode: "tclb", collectorNumber: "1")
        #expect(PreferredPrintings.key(for: token) == "name:Goblin")
    }

    @Test("A chosen printing replaces the card in a search result")
    func appliesToSearchResults() throws {
        let bolts = try printings()
        let chosen = bolts[0]   // clb
        var preferred = PreferredPrintings()
        preferred.prefer(chosen)

        let results = try searchResults()
        let shown = preferred.apply(to: results)
        #expect(shown.count == 2)
        #expect(shown[0] == chosen)
        #expect(shown[0].setCode == "clb")
        // The other card is untouched, and so is the order.
        #expect(shown[1].name == "Swords to Plowshares")
        #expect(preferred.printing(for: shown[1]) == nil)
        #expect(preferred.printing(for: bolts[2]) == chosen)
    }

    @Test("Nothing chosen leaves the list as it is")
    func emptyIsIdentity() throws {
        let results = try searchResults()
        #expect(PreferredPrintings().apply(to: results) == results)
    }

    @Test("A list of several printings of one card is left alone")
    func printingsViewKeepsEveryPrinting() throws {
        let bolts = try printings()
        var preferred = PreferredPrintings()
        preferred.prefer(bolts[1])   // 2xm

        // Every printing stays a choice; none is swapped, none repeats.
        #expect(preferred.apply(to: bolts) == bolts)
    }

    @Test("Choosing again replaces the earlier choice, also in a grid already swapped")
    func rechoosingSwapsAgain() throws {
        let bolts = try printings()
        var preferred = PreferredPrintings()
        preferred.prefer(bolts[0])
        let results = try searchResults()
        let firstGrid = preferred.apply(to: results)
        #expect(firstGrid[0].setCode == "clb")

        preferred.prefer(bolts[1])
        #expect(preferred.count == 1)
        // Back from the printings view re-applies to the grid it kept.
        let secondGrid = preferred.apply(to: firstGrid)
        #expect(secondGrid[0].setCode == "2xm")
        #expect(secondGrid[1] == firstGrid[1])
    }

    @Test("Forgetting a card shows Scryfall's printing again")
    func forgetting() throws {
        let bolts = try printings()
        var preferred = PreferredPrintings()
        preferred.prefer(bolts[0])
        preferred.forget(bolts[2])   // any printing names the card
        #expect(preferred.isEmpty)
        let results = try searchResults()
        #expect(preferred.apply(to: results) == results)

        preferred.prefer(bolts[0])
        preferred.removeAll()
        #expect(preferred.isEmpty)
    }

    @Test("The store round-trips through its file and survives a missing or broken one")
    func storeRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("preferred-printings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PreferredPrintingsStore(directory: directory)

        // Nothing saved yet, no directory yet: empty, not an error.
        #expect(store.load().isEmpty)

        let bolts = try printings()
        var preferred = PreferredPrintings()
        preferred.prefer(bolts[0])
        try store.save(preferred)
        #expect(store.load() == preferred)
        #expect(store.load().printing(for: bolts[2])?.setCode == "clb")

        try Data("not json".utf8).write(to: store.file)
        #expect(store.load().isEmpty)

        try store.clear()
        #expect(!FileManager.default.fileExists(atPath: store.file.path))
        try store.clear()   // Clearing twice is fine.
    }
}
