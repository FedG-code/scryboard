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

/// Whether the query itself sets the sort, with Scryfall's `order:` keyword.
///
/// The user's chosen order from settings is sent as a URL parameter, but a
/// query that says `order:cmc` must win, so the parameter is dropped whenever
/// the keyword is present. `direction:` (and its alias `dir:`) likewise.
/// The keyword must start a term: `o:"order:"` inside a quoted phrase is
/// rare enough not to matter, and misreading it only changes the sort.
public func specifiesOrder(_ query: String) -> Bool {
    hasKeyword("order", in: query)
}

public func specifiesDirection(_ query: String) -> Bool {
    hasKeyword("direction", in: query) || hasKeyword("dir", in: query)
}

private func hasKeyword(_ keyword: String, in query: String) -> Bool {
    query.lowercased()
        .split(whereSeparator: { $0.isWhitespace || $0 == "(" })
        .contains { term in
            var term = Substring(term)
            if term.hasPrefix("-") { term = term.dropFirst() }
            return term.hasPrefix(keyword + ":")
        }
}
