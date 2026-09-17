import Foundation

/// One page of a Scryfall `list` object, as returned by `/cards/search`.
public struct SearchPage: Codable, Hashable, Sendable {
    public let data: [Card]
    public let hasMore: Bool
    /// Absolute URL of the next page. Fetch it with ``ScryfallClient/page(at:)``
    /// so the mandatory headers are applied; never build it by hand.
    public let nextPage: URL?
    public let totalCards: Int?
    public let warnings: [String]?

    private enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
        case totalCards = "total_cards"
        case warnings
    }

    public init(
        data: [Card],
        hasMore: Bool = false,
        nextPage: URL? = nil,
        totalCards: Int? = nil,
        warnings: [String]? = nil
    ) {
        self.data = data
        self.hasMore = hasMore
        self.nextPage = nextPage
        self.totalCards = totalCards
        self.warnings = warnings
    }
}

/// A Scryfall `catalog` object — the shape `/cards/autocomplete` returns.
public struct Catalog: Codable, Hashable, Sendable {
    public let data: [String]
    public let totalValues: Int?

    private enum CodingKeys: String, CodingKey {
        case data
        case totalValues = "total_values"
    }

    public init(data: [String], totalValues: Int? = nil) {
        self.data = data
        self.totalValues = totalValues
    }
}
