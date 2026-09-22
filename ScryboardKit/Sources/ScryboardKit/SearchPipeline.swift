import Foundation

/// What the search pipeline emits.
///
/// Every case but ``idle`` carries the query it belongs to, so a UI that missed
/// an event can tell whether what it is holding is still current.
public enum SearchOutcome: Sendable, Hashable {
    /// The search bar is empty. Clear the suggestion strip and show recents.
    case idle
    /// A search is in flight. Show a spinner in the grid.
    case loading(query: String)
    /// The search was valid and Scryfall had nothing for it. An empty state,
    /// not an error — Scryfall reports a search that matched nothing as a 404,
    /// and showing that to the user as a failure would be wrong.
    case empty(query: String)
    /// Name suggestions for the strip above the keys. An empty list means
    /// "nothing to suggest" — clear the strip, do not show an empty state.
    case names([String], query: String)
    /// A page of cards for the grid.
    case cards(SearchPage, query: String)
    /// A search failed. Cancellations are never reported here, and neither are
    /// suggestion failures: a strip that stays empty is the whole consequence.
    case failure(ScryboardError, query: String)

    /// The query this outcome describes, or `nil` for ``idle``.
    public var query: String? {
        switch self {
        case .idle: nil
        case .loading(let query), .empty(let query), .names(_, let query),
             .cards(_, let query), .failure(_, let query): query
        }
    }
}

/// The search bar's brain: name suggestions while the user types, a search
/// when they commit.
///
/// The keyboard opens on a grid and only shows its QWERTY while the search bar
/// is being edited, so nothing card-shaped is on screen during typing. That is
/// why keystrokes drive only `/cards/autocomplete` (cheap, built for it) and the
/// expensive `/cards/search` waits for the Search key or a tapped suggestion.
/// Keeping this in the client layer rather than the UI is what keeps Scryboard
/// well under Scryfall's 10 requests/second, and both iOS targets plus the
/// eventual Kotlin port inherit the behaviour instead of reimplementing it.
///
/// Feed keystrokes to ``typed(_:)``, commits to ``search(_:)`` or
/// ``searchExact(name:)``, and consume ``outcomes``. Each call cancels whatever
/// the previous one started; a cancelled request emits nothing at all.
public actor SearchPipeline {
    /// Injected so tests can drive the debounce without wall-clock waits.
    public typealias Sleeper = @Sendable (Duration) async throws -> Void

    /// Short: `/cards/autocomplete` is built to be hit per keystroke, this only
    /// collapses bursts from fast typing.
    public static let defaultAutocompleteDelay = Duration.milliseconds(150)

    /// The production debounce.
    ///
    /// Held as a stored closure rather than written inline as the `sleep:`
    /// default argument: an `await` inside a default-argument expression is
    /// compiled into a thunk that, when called across a module boundary, frees
    /// concurrency task-allocator frames out of order and aborts the process
    /// ("freed pointer was not the last allocation"). Referencing a stored value
    /// keeps the default argument synchronous and sidesteps it.
    public static let liveSleeper: Sleeper = { try await Task.sleep(for: $0) }

    private let client: ScryfallClient
    private let autocompleteDelay: Duration
    private let sleep: Sleeper
    private let continuation: AsyncStream<SearchOutcome>.Continuation
    private var inFlight: Task<Void, Never>?

    /// The stream of results. One consumer; iterate it from the UI.
    public nonisolated let outcomes: AsyncStream<SearchOutcome>

    public init(
        client: ScryfallClient,
        autocompleteDelay: Duration = SearchPipeline.defaultAutocompleteDelay,
        sleep: @escaping Sleeper = SearchPipeline.liveSleeper
    ) {
        self.client = client
        self.autocompleteDelay = autocompleteDelay
        self.sleep = sleep
        let (stream, continuation) = AsyncStream<SearchOutcome>.makeStream(
            bufferingPolicy: .unbounded
        )
        self.outcomes = stream
        self.continuation = continuation
    }

    deinit {
        inFlight?.cancel()
        continuation.finish()
    }

    // MARK: - Typing

    /// Hand the pipeline the search bar's contents after a keystroke.
    ///
    /// Plain text is completed as a card name after a short debounce. Input that
    /// carries query syntax has nothing to suggest, so the strip is cleared at
    /// once and no request leaves the device. An empty bar reports ``idle``.
    public func typed(_ query: String) {
        inFlight?.cancel()
        inFlight = nil

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            continuation.yield(.idle)
            return
        }
        guard classify(trimmed) == .autocomplete else {
            continuation.yield(.names([], query: trimmed))
            return
        }

        inFlight = Task { [client, sleep, autocompleteDelay, continuation] in
            do {
                try await sleep(autocompleteDelay)
                try Task.checkCancellation()
                let names = try await client.autocomplete(trimmed)
                try Task.checkCancellation()
                continuation.yield(.names(names, query: trimmed))
            } catch is CancellationError {
                // Superseded by a newer keystroke. Say nothing.
            } catch {
                // A suggestion strip that stays empty is the whole consequence
                // of a failed autocomplete; the user can still press Search,
                // and that path does report failures.
                guard !Task.isCancelled else { return }
                continuation.yield(.names([], query: trimmed))
            }
        }
    }

    // MARK: - Committing

    /// Run the query as it stands. The Search key.
    ///
    /// Scryfall matches bare words against card names, so plain text needs no
    /// translation: `lightning` returns every card with that word in its name.
    public func search(
        _ query: String,
        unique: SearchUniqueness = .cards,
        order: SearchOrder = .name,
        direction: SortDirection = .auto
    ) {
        inFlight?.cancel()
        inFlight = nil

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            continuation.yield(.idle)
            return
        }

        continuation.yield(.loading(query: trimmed))
        inFlight = Task { [client, continuation] in
            do {
                let page = try await client.search(
                    trimmed, unique: unique, order: order, direction: direction
                )
                try Task.checkCancellation()
                continuation.yield(
                    page.data.isEmpty ? .empty(query: trimmed) : .cards(page, query: trimmed)
                )
            } catch is CancellationError {
                // Superseded by a newer search. Say nothing.
            } catch let error as ScryboardError {
                guard !Task.isCancelled else { return }
                // "Nothing matched" arrives as a 404. That is an empty result,
                // not something to apologise for.
                continuation.yield(
                    error.isNotFound
                        ? .empty(query: trimmed)
                        : .failure(error, query: trimmed)
                )
            } catch {
                guard !Task.isCancelled else { return }
                continuation.yield(
                    .failure(.transport(.other, message: String(describing: error)), query: trimmed)
                )
            }
        }
    }

    /// Every printing of one card, newest first. A tapped suggestion.
    ///
    /// This is the printing picker: the grid fills with each printing of the
    /// chosen name and the user picks the art they want to send.
    public func searchExact(name: String) {
        // `!"…"` is Scryfall's exact-name operator. Card names never contain a
        // double quote, so this needs no escaping.
        search("!\"\(name)\"", unique: .prints, order: .released, direction: .descending)
    }

    // MARK: - Lifecycle

    /// Drop any in-flight or pending request and report an empty search bar.
    public func cancel() {
        inFlight?.cancel()
        inFlight = nil
        continuation.yield(.idle)
    }

    /// Drop any in-flight or pending request and say nothing. For a caller
    /// that already has what it wants to show, such as Back from the
    /// printings view restoring the grid it kept; ``cancel()`` would report
    /// ``SearchOutcome/idle`` and wipe it.
    public func drop() {
        inFlight?.cancel()
        inFlight = nil
    }

    /// Close ``outcomes``. The pipeline is unusable afterwards.
    public func finish() {
        inFlight?.cancel()
        inFlight = nil
        continuation.finish()
    }
}
