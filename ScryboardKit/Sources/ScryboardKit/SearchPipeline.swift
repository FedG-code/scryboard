import Foundation

/// What the search pipeline emits for a given piece of input.
///
/// Every case but ``idle`` carries the query it belongs to, so a UI that missed
/// an event can tell whether what it is holding is still current.
public enum SearchOutcome: Sendable, Hashable {
    /// The search bar is empty. Clear the grid.
    case idle
    /// Debounce elapsed, request in flight. Show a spinner.
    case loading(query: String)
    /// The query was valid and Scryfall had nothing for it. An empty state, not
    /// an error — Scryfall reports a search that matched nothing as a 404, and
    /// showing that to the user as a failure would be wrong.
    case empty(query: String)
    /// Name suggestions from `/cards/autocomplete`.
    case names([String], query: String)
    /// A page of cards from `/cards/search`.
    case cards(SearchPage, query: String)
    /// The request failed. Cancellations are never reported here.
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

/// Debounce-and-cancel in front of ``ScryfallClient``.
///
/// This lives in the client layer, not the UI, for two reasons: it is what keeps
/// Scryboard well under Scryfall's 10 requests/second, and both iOS targets plus
/// the eventual Kotlin port inherit the behaviour instead of reimplementing it.
///
/// Feed it keystrokes with ``submit(_:)`` and consume ``outcomes``. Each new
/// query cancels the previous one, in its debounce window or mid-flight; a
/// cancelled query emits nothing at all.
public actor SearchPipeline {
    /// Injected so tests can drive the debounce without wall-clock waits.
    public typealias Sleeper = @Sendable (Duration) async throws -> Void

    /// Short: `/cards/autocomplete` is built to be hit per keystroke, this only
    /// collapses bursts from fast typing.
    public static let defaultAutocompleteDelay = Duration.milliseconds(150)
    /// Longer: a full search is expensive and users type syntax in chunks.
    public static let defaultSearchDelay = Duration.milliseconds(300)

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
    private let searchDelay: Duration
    private let sleep: Sleeper
    private let continuation: AsyncStream<SearchOutcome>.Continuation
    private var inFlight: Task<Void, Never>?

    /// The stream of results. One consumer; iterate it from the UI.
    public nonisolated let outcomes: AsyncStream<SearchOutcome>

    public init(
        client: ScryfallClient,
        autocompleteDelay: Duration = SearchPipeline.defaultAutocompleteDelay,
        searchDelay: Duration = SearchPipeline.defaultSearchDelay,
        sleep: @escaping Sleeper = SearchPipeline.liveSleeper
    ) {
        self.client = client
        self.autocompleteDelay = autocompleteDelay
        self.searchDelay = searchDelay
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

    /// Hand the pipeline the search bar's current contents. Safe to call on
    /// every keystroke.
    public func submit(_ query: String) {
        inFlight?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            inFlight = nil
            continuation.yield(.idle)
            return
        }

        let kind = classify(trimmed)
        let delay = kind == .autocomplete ? autocompleteDelay : searchDelay

        inFlight = Task { [client, sleep, continuation] in
            do {
                try await sleep(delay)
                try Task.checkCancellation()
                continuation.yield(.loading(query: trimmed))

                let outcome: SearchOutcome
                switch kind {
                case .autocomplete:
                    let names = try await client.autocomplete(trimmed)
                    outcome = names.isEmpty
                        ? .empty(query: trimmed)
                        : .names(names, query: trimmed)
                case .search:
                    let page = try await client.search(trimmed)
                    outcome = page.data.isEmpty
                        ? .empty(query: trimmed)
                        : .cards(page, query: trimmed)
                }

                try Task.checkCancellation()
                continuation.yield(outcome)
            } catch is CancellationError {
                // Superseded by a newer query. Say nothing.
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

    /// Drop any in-flight or pending query and report an empty search bar.
    public func cancel() {
        inFlight?.cancel()
        inFlight = nil
        continuation.yield(.idle)
    }

    /// Close ``outcomes``. The pipeline is unusable afterwards.
    public func finish() {
        inFlight?.cancel()
        inFlight = nil
        continuation.finish()
    }
}
