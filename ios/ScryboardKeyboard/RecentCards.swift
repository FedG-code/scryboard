import Foundation
import ScryboardKit

/// The cards the user has copied, newest first, kept in the extension's own
/// defaults. Whole `Card` objects are stored so the grid renders them exactly
/// like search results, with no round trip to Scryfall.
enum RecentCards {
    private static let key = "recentCards"
    private static let limit = 30

    static func load() -> [Card] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Card].self, from: data)) ?? []
    }

    static func remember(_ card: Card) {
        var cards = load().filter { $0.id != card.id }
        cards.insert(card, at: 0)
        if cards.count > limit { cards.removeLast(cards.count - limit) }
        if let data = try? JSONEncoder().encode(cards) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
