import Foundation

/// The printing the user chose for each card, so that card shows as that
/// printing from then on.
///
/// A search returns one printing per card, whichever Scryfall ranks first.
/// Holding a card opens every printing of it; the one the user then copies
/// is remembered here, and every later grid that card appears in swaps it
/// for the chosen printing before anything is drawn or copied. Commander
/// players send the same art every time; this saves them the hold.
///
/// Keyed by `oracle_id`, the identifier that is stable across printings,
/// falling back to the name for the rare card object that arrives without
/// one (tokens, the faces of reversible cards), as the printings query does.
/// Pure data, Foundation only, like the rest of the Kit; `PreferredPrintingsStore`
/// keeps it on disk.
public struct PreferredPrintings: Codable, Hashable, Sendable {
    /// The chosen printing per ``key(for:)``.
    public private(set) var printings: [String: Card]

    public init(printings: [String: Card] = [:]) {
        self.printings = printings
    }

    public var isEmpty: Bool { printings.isEmpty }
    public var count: Int { printings.count }

    /// What identifies a card across its printings.
    public static func key(for card: Card) -> String {
        if let oracleID = card.oracleID {
            return "oracle:\(oracleID.uuidString.lowercased())"
        }
        return "name:\(card.name)"
    }

    /// The printing chosen for `card`, if any. `card` may be any printing.
    public func printing(for card: Card) -> Card? {
        printings[Self.key(for: card)]
    }

    /// Make `card` the printing shown for its name. Replaces an earlier choice.
    public mutating func prefer(_ card: Card) {
        printings[Self.key(for: card)] = card
    }

    /// Back to whatever Scryfall returns for the card.
    public mutating func forget(_ card: Card) {
        printings.removeValue(forKey: Self.key(for: card))
    }

    public mutating func removeAll() {
        printings.removeAll()
    }

    /// `cards` with every card that has a chosen printing swapped for it.
    ///
    /// Only a card that appears once in the list is swapped. A list holding
    /// several printings of one card is a printings view, or a `unique:prints`
    /// search, and there every printing is a choice: collapsing them into the
    /// chosen one would hide the others. Order and count are kept, so the
    /// caller can index the result as it indexed the input; a card already
    /// swapped keeps its key, so applying again after a new choice swaps it
    /// again.
    public func apply(to cards: [Card]) -> [Card] {
        guard !printings.isEmpty else { return cards }
        var occurrences: [String: Int] = [:]
        for card in cards {
            occurrences[Self.key(for: card), default: 0] += 1
        }
        return cards.map { card in
            let key = Self.key(for: card)
            guard occurrences[key] == 1, let preferred = printings[key] else { return card }
            return preferred
        }
    }
}

/// ``PreferredPrintings`` as one JSON file.
///
/// The file belongs somewhere the system does not purge (Application
/// Support, not caches): a choice is the user's, not a cache. Reads and
/// writes are synchronous; the file is small, a kilobyte or two a card.
public struct PreferredPrintingsStore: Sendable {
    public static let fileName = "preferred-printings.json"

    public let file: URL

    public init(file: URL) {
        self.file = file
    }

    /// The store's file inside `directory`, which is created on the first save.
    public init(directory: URL) {
        self.init(file: directory.appendingPathComponent(PreferredPrintingsStore.fileName))
    }

    /// What was saved, or nothing when the file is missing or unreadable:
    /// a choice that cannot be read back is forgotten, not an error.
    public func load() -> PreferredPrintings {
        guard let data = try? Data(contentsOf: file),
              let printings = try? JSONDecoder().decode(PreferredPrintings.self, from: data)
        else { return PreferredPrintings() }
        return printings
    }

    public func save(_ printings: PreferredPrintings) throws {
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(printings)
        try data.write(to: file, options: .atomic)
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }
}
