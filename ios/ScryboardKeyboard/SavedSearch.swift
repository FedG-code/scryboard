import Foundation

/// The last committed search, kept so the grid comes back where the user left
/// it. The host app rebuilds the keyboard on every dismissal, and pasting a
/// card dismisses it, so without this the grid reset to recents after each
/// copy. Expires after ten minutes; the clear button removes it at once.
///
/// Only the queries are stored; results are fetched again on restore. Storing
/// the first page as well would avoid a flicker and a request — a later pass.
struct SavedSearch: Codable, Equatable {
    /// What the user typed. Stays in the pill even while printings are shown,
    /// and is what Back returns to. Empty when the grid was recents.
    var query: String
    /// The held card whose printings fill the grid, if any.
    var printings: String?
    var savedAt: Date

    static let lifetime: TimeInterval = 10 * 60
    private static let key = "savedSearch"

    static func load(now: Date = Date()) -> SavedSearch? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode(SavedSearch.self, from: data),
              now.timeIntervalSince(saved.savedAt) < lifetime
        else { return nil }
        return saved
    }

    static func remember(query: String, printings: String?) {
        guard !query.isEmpty || printings != nil else {
            clear()
            return
        }
        let saved = SavedSearch(query: query, printings: printings, savedAt: Date())
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
