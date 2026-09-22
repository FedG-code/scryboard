import Foundation
import ScryboardKit

/// The last committed search, kept so the grid comes back where the user left
/// it. The host app rebuilds the keyboard on every dismissal, and pasting a
/// card dismisses it, so without this the grid reset to recents after each
/// copy. Expires after ten minutes; the clear button removes it at once.
///
/// This record is small and lives in `UserDefaults`. The results themselves
/// go through ``SavedResults`` to a file in the caches directory, tagged with
/// `resultsID` so a purged or stale file is never mistaken for the current
/// search; when the file is gone the query is simply run again.
struct SavedSearch: Codable, Equatable {
    /// What the user typed. Stays in the pill even while printings are shown,
    /// and is what Back returns to. Empty when the grid was recents.
    var query: String
    /// The held card whose printings fill the grid, if any.
    var printings: String?
    /// The card at the top of the grid when it was last seen.
    var firstVisible: Int = 0
    /// Ties this record to the results file written for it.
    var resultsID: UUID = UUID()
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

    /// A new search or printings view. Starts a fresh results file and
    /// forgets the old position.
    static func remember(query: String, printings: String?) {
        guard !query.isEmpty || printings != nil else {
            clear()
            return
        }
        save(SavedSearch(query: query, printings: printings, savedAt: Date()))
    }

    /// The grid moved. Keeps the record alive too: scrolling is activity.
    static func rememberPosition(_ firstVisible: Int) {
        guard var saved = load() else { return }
        saved.firstVisible = firstVisible
        saved.savedAt = Date()
        save(saved)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func save(_ saved: SavedSearch) {
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// The pages a search had loaded, on disk, so a rebuilt keyboard shows the
/// grid as far as the user had scrolled it without fetching them again.
///
/// One file in the caches directory, which the system may purge; card data
/// is small (about a kilobyte a card) and expires with ``SavedSearch``. An
/// actor with synchronous file work inside, so stores land in the order
/// they were requested; `sequence` guards the rare case that they do not.
actor SavedResults {
    static let shared = SavedResults()

    private struct Stored: Codable {
        var id: UUID
        var page: SearchPage
    }

    private let file: URL
    private var lastSequence = 0

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        file = caches.appendingPathComponent("saved-results.json")
    }

    /// Write `page` as the results for the search tagged `id`. A store with
    /// a lower `sequence` than one already written is stale and skipped.
    func store(_ page: SearchPage, id: UUID, sequence: Int) {
        guard sequence > lastSequence else { return }
        lastSequence = sequence
        guard let data = try? JSONEncoder().encode(Stored(id: id, page: page)) else { return }
        try? data.write(to: file, options: .atomic)
    }

    /// The results written for `id`, if the file is still there and is theirs.
    func load(id: UUID) -> SearchPage? {
        guard let data = try? Data(contentsOf: file),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.id == id
        else { return nil }
        return stored.page
    }

    func clear() {
        try? FileManager.default.removeItem(at: file)
    }
}
