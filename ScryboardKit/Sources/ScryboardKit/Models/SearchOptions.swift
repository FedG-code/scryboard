import Foundation

/// `unique=` — how Scryfall collapses duplicate results.
public enum SearchUniqueness: String, Sendable, Hashable, CaseIterable {
    /// One row per card, however many times it has been printed. The default,
    /// and what the results grid wants.
    case cards
    /// One row per printing. What the printing picker wants.
    case prints
    /// One row per distinct illustration — printings that reuse an existing
    /// piece of art collapse together.
    case art
}

/// `order=` — the sort Scryfall applies before paginating.
///
/// A closed enum rather than an open wrapper, unlike ``Layout``: these are
/// values Scryboard sends, not values it has to survive receiving.
public enum SearchOrder: String, Sendable, Hashable, CaseIterable, Codable {
    case name, set, released, rarity, color, usd, tix, eur, cmc, power, toughness,
         edhrec, penny, artist, review

    /// How the settings screen names the order. Scryfall's own labels.
    public var title: String {
        switch self {
        case .name: "Name"
        case .set: "Set and number"
        case .released: "Release date"
        case .rarity: "Rarity"
        case .color: "Color"
        case .usd: "Price: USD"
        case .tix: "Price: MTGO tix"
        case .eur: "Price: EUR"
        case .cmc: "Mana value"
        case .power: "Power"
        case .toughness: "Toughness"
        case .edhrec: "EDHREC rank"
        case .penny: "Penny Dreadful rank"
        case .artist: "Artist"
        case .review: "Set review order"
        }
    }
}

/// `dir=` — which way ``SearchOrder`` runs.
public enum SortDirection: String, Sendable, Hashable, CaseIterable, Codable {
    /// Let Scryfall pick whatever is natural for the chosen order.
    case auto
    case ascending = "asc"
    case descending = "desc"

    public var title: String {
        switch self {
        case .auto: "Automatic"
        case .ascending: "Ascending"
        case .descending: "Descending"
        }
    }
}
