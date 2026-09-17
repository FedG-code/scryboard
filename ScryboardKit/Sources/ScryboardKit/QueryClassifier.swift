import Foundation

/// Which Scryfall endpoint a piece of search-bar input should be routed to.
public enum QueryKind: String, Sendable, Hashable, CaseIterable {
    /// `/cards/autocomplete` — name suggestions, built to be hit per keystroke.
    case autocomplete
    /// `/cards/search` — the full query language, debounced and cancellable.
    case search
}

extension QueryKind {
    /// Characters that can only appear in Scryfall's query language, never in a
    /// card name the user is part-way through typing.
    ///
    /// The apostrophe is deliberately absent. Scryfall accepts `'` as a quoting
    /// character, but card names are full of it — Gaea's Cradle, Urza's Tower,
    /// Sensei's Divining Top — and routing those to `/cards/search` would break
    /// name completion for a large slice of the card pool. Users who want a
    /// quoted phrase can type `"`.
    public static let syntaxCharacters: Set<Character> = [":", "<", ">", "=", "\""]
}

/// Routes search-bar input by shape: plain text completes names, anything
/// carrying query syntax goes to the full search endpoint.
///
/// Pure and total by design — it is the piece of logic the Kotlin port copies
/// line for line, and the unit tests are its specification.
public func classify(_ query: String) -> QueryKind {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .autocomplete }
    return trimmed.contains(where: QueryKind.syntaxCharacters.contains) ? .search : .autocomplete
}
