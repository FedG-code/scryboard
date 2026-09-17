import Testing
@testable import ScryboardKit

/// The routing spec. These cases are the contract the Kotlin port is written
/// against, so they are deliberately exhaustive about the edges.
@Suite("Query classification")
struct QueryClassifierTests {
    @Test(
        "Plain names complete",
        arguments: [
            "bolt",
            "Lightning Bolt",
            "l",
            "sol ring",
            "  Counterspell  ",
            "Jace, the Mind Sculptor",
            "Borborygmos Enraged",
            "Ætherling",
            "Márton Stromgald",
            "Fire // Ice",
            "Look at Me, I'm the DM",
            "-1/-1 counters",
        ]
    )
    func plainTextRoutesToAutocomplete(_ query: String) {
        #expect(classify(query) == .autocomplete)
    }

    @Test(
        "Syntax routes to search",
        arguments: [
            "otag:removal",
            "is:commander",
            "cmc<=3",
            "cmc>5",
            "pow>=4",
            "c=wu",
            "t:goblin",
            "o:\"draw a card\"",
            "\"Lightning Bolt\"",
            "set:neo r:mythic",
            "bolt cmc<2",
            "oracle:flying legal:modern",
        ]
    )
    func syntaxRoutesToSearch(_ query: String) {
        #expect(classify(query) == .search)
    }

    /// Card names are full of apostrophes. Treating `'` as a syntax character
    /// would break completion for a large slice of the card pool, so it is
    /// excluded even though Scryfall accepts it as a quote character.
    @Test(
        "Apostrophes in names still complete",
        arguments: [
            "Gaea's Cradle",
            "Urza's Tower",
            "Sensei's Divining Top",
            "gaea's",
            "Yawgmoth's Will",
        ]
    )
    func apostrophesDoNotTriggerSearch(_ query: String) {
        #expect(classify(query) == .autocomplete)
    }

    @Test("Empty and whitespace-only input completes", arguments: ["", " ", "\n", "\t  \n"])
    func emptyInputIsAutocomplete(_ query: String) {
        #expect(classify(query) == .autocomplete)
    }

    @Test("A single syntax character anywhere is enough")
    func oneOperatorSuffices() {
        #expect(classify("bolt:") == .search)
        #expect(classify(":") == .search)
        #expect(classify("a<b") == .search)
        #expect(classify("lightning bolt =") == .search)
    }

    @Test("Classification ignores surrounding whitespace")
    func whitespaceIsTrimmed() {
        #expect(classify("   otag:removal   ") == .search)
        #expect(classify("   bolt   ") == .autocomplete)
    }

    @Test("Classification is pure")
    func repeatedCallsAgree() {
        for query in ["bolt", "otag:removal", "", "Gaea's Cradle"] {
            #expect(classify(query) == classify(query))
        }
    }
}
