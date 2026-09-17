import Foundation

/// Accumulates the pages of one search as the grid scrolls.
///
/// The grid shows a flat list of cards; Scryfall hands them over 175 at a time.
/// This owns the seam: when to ask for more, how to not ask twice at once, and
/// what the flat list looks like afterwards. An actor because the scroll view
/// will call it from the main actor while a fetch is in flight.
public actor ResultsPager {
    /// Everything fetched so far, in Scryfall's order.
    public private(set) var cards: [Card]
    /// A fetch is in flight. The grid shows a footer spinner on this.
    public private(set) var isLoadingMore = false
    /// The last fetch that failed, if the most recent one did. Cleared by a
    /// successful load. Scroll-driven prefetching reports failures here rather
    /// than throwing into a scroll callback.
    public private(set) var lastFailure: ScryboardError?

    private let client: ScryfallClient
    private let prefetchDistance: Int
    private var nextPageURL: URL?
    private var seenIDs: Set<UUID>

    /// Total across all pages, as Scryfall reported it on the first page.
    public let totalCards: Int?

    /// - Parameter prefetchDistance: how close to the end of the loaded cards
    ///   the grid has to scroll before the next page is requested. Twelve is
    ///   about two rows of thumbnails — enough to hide the latency, small enough
    ///   that an idle browse does not pull pages the user never sees.
    public init(client: ScryfallClient, firstPage: SearchPage, prefetchDistance: Int = 12) {
        self.client = client
        self.prefetchDistance = prefetchDistance
        self.cards = firstPage.data
        self.seenIDs = Set(firstPage.data.map(\.id))
        self.nextPageURL = firstPage.hasMore ? firstPage.nextPage : nil
        self.totalCards = firstPage.totalCards
    }

    /// `true` while Scryfall still has pages for this search.
    public var canLoadMore: Bool { nextPageURL != nil }

    /// Call as cells come on screen. Fetches the next page once the index is
    /// within ``prefetchDistance`` of the end, and does nothing otherwise.
    public func cardAppeared(at index: Int) async {
        guard canLoadMore, !isLoadingMore else { return }
        guard index >= cards.count - prefetchDistance else { return }
        _ = try? await loadMore()
    }

    /// Fetch the next page and append it.
    ///
    /// - Returns: `true` if anything was appended. `false` means there was
    ///   nothing left to fetch, or a fetch was already running.
    @discardableResult
    public func loadMore() async throws -> Bool {
        guard let url = nextPageURL, !isLoadingMore else { return false }

        isLoadingMore = true
        defer { isLoadingMore = false }

        let page: SearchPage
        do {
            page = try await client.page(at: url)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ScryboardError {
            lastFailure = error
            throw error
        }

        lastFailure = nil
        nextPageURL = page.hasMore ? page.nextPage : nil

        // Scryfall does not repeat cards across pages, but `unique:prints`
        // searches and a page fetched twice would both put duplicates into the
        // grid's data source. Cheap to rule out here, painful to debug later.
        let fresh = page.data.filter { seenIDs.insert($0.id).inserted }
        cards.append(contentsOf: fresh)
        return !fresh.isEmpty
    }

    /// Retry after a failure, without waiting for the grid to scroll again.
    @discardableResult
    public func retry() async throws -> Bool {
        lastFailure = nil
        return try await loadMore()
    }
}
