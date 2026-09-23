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
