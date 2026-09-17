import Foundation
import Testing
@testable import ScryboardKit

@Suite("Card decoding")
struct CardDecodingTests {
    @Test("A single-faced card decodes with its images")
    func normalCard() throws {
        let card = try Fixture.decode(Card.self, from: "card_normal")

        #expect(card.name == "Lightning Bolt")
        #expect(card.layout == .normal)
        #expect(card.setCode == "lea")
        #expect(card.setName == "Limited Edition Alpha")
        #expect(card.collectorNumber == "161")
        #expect(card.manaCost == "{R}")
        #expect(card.typeLine == "Instant")
        #expect(card.oracleText == "Lightning Bolt deals 3 damage to any target.")
        #expect(card.releasedAt == "1993-08-05")
        #expect(card.id == UUID(uuidString: "77c6fa74-5543-42ac-9ead-0e890b188e99"))
        #expect(card.oracleID == UUID(uuidString: "4457ed35-7c10-48c8-9776-456485fdf070"))
        #expect(card.cardFaces == nil)
        #expect(card.hasDistinctFaceImages == false)
    }

    /// The two sizes the product actually uses: `small` for the grid, `normal`
    /// for the pasteboard write.
    @Test("The sizes the product uses are present")
    func imageSizes() throws {
        let card = try Fixture.decode(Card.self, from: "card_normal")

        #expect(card.imageURL(.small)?.path.hasPrefix("/small/front/") == true)
        #expect(card.imageURL(.normal)?.path.hasPrefix("/normal/front/") == true)
        #expect(card.imageURL(.large) != nil)
        #expect(card.imageURL(.png)?.pathExtension == "png")
        #expect(card.imageURL(.borderCrop) != nil)
        #expect(card.frontImageURIs == card.imageURIs)
    }

    @Test("Unknown JSON keys are ignored")
    func toleratesUnmodelledFields() throws {
        // The fixture carries prices, legalities, keywords, multiverse_ids…
        // none of which are modelled. Decoding must not care.
        let card = try Fixture.decode(Card.self, from: "card_normal")
        #expect(card.name == "Lightning Bolt")
    }

    @Test("A transform card exposes the front face uniformly")
    func doubleFacedCard() throws {
        let card = try Fixture.decode(Card.self, from: "card_double_faced")

        #expect(card.layout == .transform)
        #expect(card.imageURIs == nil, "transform cards carry no top-level image_uris")
        #expect(card.cardFaces?.count == 2)
        #expect(card.cardFaces?[0].name == "Delver of Secrets")
        #expect(card.cardFaces?[1].name == "Insectile Aberration")
        #expect(card.cardFaces?[1].oracleText == "Flying")
        #expect(card.hasDistinctFaceImages)

        // The convenience the grid and the pasteboard both rely on.
        #expect(card.frontImageURIs == card.cardFaces?[0].imageURIs)
        #expect(card.imageURL(.small)?.path.contains("/front/") == true)
        #expect(card.imageURL(.normal)?.path.contains("/front/") == true)

        #expect(card.imageURIs(forFace: 0) == card.cardFaces?[0].imageURIs)
        #expect(card.imageURIs(forFace: 1) == card.cardFaces?[1].imageURIs)
        #expect(card.imageURIs(forFace: 1)?[.normal]?.path.contains("/back/") == true)
        #expect(card.imageURIs(forFace: 2) == nil)

        // What tap-to-copy uses once the user has flipped the card.
        #expect(card.imageURL(.normal, face: 0) == card.imageURL(.normal))
        #expect(card.imageURL(.normal, face: 1)?.path.contains("/back/") == true)
        #expect(card.imageURL(.small, face: 1)?.path.hasPrefix("/small/back/") == true)
        #expect(card.imageURL(.normal, face: 2) == nil)
    }

    /// Split cards have faces but one shared scan — flipping them is meaningless,
    /// and asking for face 1's image must fall back to the card's own artwork.
    @Test("A split card has faces but shares one image")
    func splitCard() throws {
        let card = try Fixture.decode(Card.self, from: "card_split")

        #expect(card.layout == .split)
        #expect(card.cardFaces?.count == 2)
        #expect(card.imageURIs != nil)
        #expect(card.hasDistinctFaceImages == false, "no flip affordance for split cards")
        #expect(card.frontImageURIs == card.imageURIs)
        #expect(card.imageURIs(forFace: 1) == card.imageURIs)
        // Flipping a split card shows the same scan, never nothing.
        #expect(card.imageURL(.normal, face: 1) == card.imageURL(.normal))
    }

    @Test("An unknown layout decodes instead of failing")
    func unknownLayout() throws {
        let json = """
        {"object":"card","id":"77c6fa74-5543-42ac-9ead-0e890b188e99",
         "name":"Something New","layout":"quadruple_faced_vertical",
         "set":"xyz","collector_number":"1"}
        """
        let card = try JSONDecoder().decode(Card.self, from: Data(json.utf8))
        #expect(card.layout.rawValue == "quadruple_faced_vertical")
        #expect(card.layout != .normal)
    }

    @Test("Cards round-trip through Codable")
    func roundTrip() throws {
        for name in ["card_normal", "card_double_faced", "card_split"] {
            let card = try Fixture.decode(Card.self, from: name)
            let reencoded = try JSONEncoder().encode(card)
            let decoded = try JSONDecoder().decode(Card.self, from: reencoded)
            #expect(decoded == card)
        }
    }
}

@Suite("List and catalog decoding")
struct ListDecodingTests {
    @Test("A search page exposes its cards and its cursor")
    func searchPage() throws {
        let page = try Fixture.decode(SearchPage.self, from: "search_page")

        #expect(page.totalCards == 1287)
        #expect(page.hasMore)
        #expect(page.data.count == 2)
        #expect(page.data.map(\.name) == ["Lightning Bolt", "Swords to Plowshares"])
        #expect(page.data[0].imageURL(.small) != nil)
        #expect(page.nextPage?.absoluteString.contains("page=2") == true)
        #expect(page.nextPage?.host == "api.scryfall.com")
    }

    @Test("The last page has no cursor")
    func lastPage() throws {
        let page = try Fixture.decode(SearchPage.self, from: "search_page_last")

        #expect(page.hasMore == false)
        #expect(page.nextPage == nil)
        #expect(page.data.count == 1)
        // Optional fields absent from the payload stay nil rather than failing.
        #expect(page.data[0].oracleID == nil)
        #expect(page.data[0].setName == nil)
        #expect(page.data[0].scryfallURI == nil)
    }

    @Test("Autocomplete decodes as a catalog of names")
    func catalog() throws {
        let catalog = try Fixture.decode(Catalog.self, from: "autocomplete")

        #expect(catalog.totalValues == 6)
        #expect(catalog.data.count == 6)
        #expect(catalog.data.first == "Lightning Bolt")
    }
}

@Suite("Error object decoding")
struct ErrorDecodingTests {
    @Test("A 404 decodes as a not-found Scryfall error")
    func notFound() throws {
        let error = try Fixture.decode(ScryfallError.self, from: "error_not_found")

        #expect(error.status == 404)
        #expect(error.code == "not_found")
        #expect(error.isNotFound)
        #expect(error.details.hasPrefix("Your query didn't match any cards."))
        #expect(error.warnings == nil)
    }

    @Test("A 400 keeps the syntax warnings Scryfall sends back")
    func badRequest() throws {
        let error = try Fixture.decode(ScryfallError.self, from: "error_bad_request")

        #expect(error.status == 400)
        #expect(error.code == "bad_request")
        #expect(error.isNotFound == false)
        #expect(error.details == "All of your terms were ignored.")
        #expect(error.warnings?.count == 1)
        #expect(error.warnings?[0].contains("frobnicate") == true)
    }

    @Test("Scryfall's details are what the UI shows")
    func errorDescriptionUsesDetails() throws {
        let error = try Fixture.decode(ScryfallError.self, from: "error_not_found")
        let wrapped = ScryboardError.scryfall(error)

        #expect(wrapped.errorDescription == error.details)
        #expect(wrapped.scryfallError == error)
        #expect(wrapped.isNotFound)
        #expect(ScryboardError.transport(.offline, message: "x").isNotFound == false)
        #expect(ScryboardError.transport(.offline, message: "x").scryfallError == nil)
    }
}
