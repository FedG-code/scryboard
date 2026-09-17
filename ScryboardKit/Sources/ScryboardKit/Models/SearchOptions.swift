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
public enum SearchOrder: String, Sendable, Hashable, CaseIterable {
    case name, set, released, rarity, color, cmc, power, toughness, artist, edhrec
}

/// `dir=` — which way ``SearchOrder`` runs.
public enum SortDirection: String, Sendable, Hashable, CaseIterable {
    /// Let Scryfall pick whatever is natural for the chosen order.
    case auto
    case ascending = "asc"
    case descending = "desc"
}
