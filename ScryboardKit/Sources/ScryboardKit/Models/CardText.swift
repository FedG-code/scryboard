import Foundation

/// Plain-text forms of a card for the "copy as text" setting.
///
/// Foundation only, like the rest of the Kit, so the Android port gets the
/// same strings from the same spec.
extension Card {
    /// The card as one decklist line in the form Arena, Moxfield, Archidekt
    /// and Scryfall's own deck export all accept:
    ///
    ///     Lightning Bolt (LEA) 161
    ///
    /// Scryfall gives set codes in lower case; the deck builders print them in
    /// upper case, so that is what is copied. No leading quantity: the text
    /// goes into a chat, not a deck, and the deck builders read it without one.
    public var decklistLine: String {
        "\(name) (\(setCode.uppercased())) \(collectorNumber)"
    }
}

extension Card {
    /// The card's page on scryfall.com, clean. The API's `scryfall_uri`
    /// carries `?utm_source=api`, which is Scryfall's own analytics and only
    /// noise in a chat, so the query is dropped before the link is shared.
    public var pageURL: URL? {
        guard let scryfallURI,
              var components = URLComponents(url: scryfallURI, resolvingAgainstBaseURL: false)
        else { return nil }
        components.query = nil
        return components.url
    }
}
