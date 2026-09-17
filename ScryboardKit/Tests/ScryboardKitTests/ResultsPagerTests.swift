import Foundation
import Testing
@testable import ScryboardKit

/// The grid's paging seam: when to ask Scryfall for more, and how not to ask twice.
@Suite("Results paging")
struct ResultsPagerTests {
    private func makeClient(log: RequestLog = RequestLog()) -> ScryfallClient {
        ScryfallClient(transport: StubTransport(log: log) { request in
            let fixture = request.url?.query?.contains("page=2") == true
                ? "search_page_last"
                : "search_page"
            return (try Fixture.data(fixture), .stub(200, for: request))
        })
    }

    @Test("The first page is available without a fetch")
    func startsWithFirstPage() async throws {
        let log = RequestLog()
        let page = try Fixture.decode(SearchPage.self, from: "search_page")
        let pager = ResultsPager(client: makeClient(log: log), firstPage: page)

        #expect(await pager.cards.count == 2)
        #expect(await pager.totalCards == 1287)
        #expect(await pager.canLoadMore)
        #expect(await log.count == 0)
    }

    @Test("Loading more appends the next page")
    func appendsNextPage() async throws {
        let log = RequestLog()
        let page = try Fixture.decode(SearchPage.self, from: "search_page")
        let pager = ResultsPager(client: makeClient(log: log), firstPage: page)

        #expect(try await pager.loadMore())
        #expect(await pager.cards.map(\.name) == ["Lightning Bolt", "Swords to Plowshares", "Terror"])
        #expect(await pager.canLoadMore == false)
        #expect(await log.count == 1)
        #expect(await log.urls.last?.query?.contains("page=2") == true)
    }

    @Test("A search with one page never fetches")
    func singlePageSearch() async throws {
        let log = RequestLog()
        let page = try Fixture.decode(SearchPage.self, from: "search_page_last")
        let pager = ResultsPager(client: makeClient(log: log), firstPage: page)

        #expect(await pager.canLoadMore == false)
        #expect(try await pager.loadMore() == false)
        await pager.cardAppeared(at: 0)
        #expect(await log.count == 0)
    }

    @Test("Scrolling near the end triggers a fetch, scrolling in the middle does not")
    func prefetchDistance() async throws {
        let log = RequestLog()
        let page = try Fixture.decode(SearchPage.self, from: "search_page")
        // Two cards loaded, so anything from index 1 onward is within one of the end.
        let pager = ResultsPager(client: makeClient(log: log), firstPage: page, prefetchDistance: 1)

        await pager.cardAppeared(at: 0)
        #expect(await log.count == 0, "the middle of the list must not pull a page")

        await pager.cardAppeared(at: 1)
        #expect(await log.count == 1)
        #expect(await pager.cards.count == 3)
    }

    /// A fast scroll fires appearance callbacks for a dozen cells at once. Each
    /// one must not start its own request.
    @Test("A burst of appearances causes one fetch")
    func concurrentAppearancesFetchOnce() async throws {
        let log = RequestLog()
        let page = try Fixture.decode(SearchPage.self, from: "search_page")
        let pager = ResultsPager(client: makeClient(log: log), firstPage: page, prefetchDistance: 4)

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<12 {
                group.addTask { await pager.cardAppeared(at: index) }
            }
        }

        #expect(await log.count == 1)
        #expect(await pager.cards.count == 3)
    }

    @Test("Duplicate cards are not appended twice")
    func deduplicates() async throws {
        let log = RequestLog()
        // Both pages carry the same cards; the second must add nothing.
        let client = ScryfallClient(transport: StubTransport(log: log, fixture: "search_page"))
        let page = try Fixture.decode(SearchPage.self, from: "search_page")
        let pager = ResultsPager(client: client, firstPage: page)

        #expect(try await pager.loadMore() == false)
        #expect(await pager.cards.count == 2)
    }

    @Test("A failed page is reported and retryable")
    func failureIsRecoverable() async throws {
        let log = RequestLog()
        let attempt = Counter()
        let client = ScryfallClient(transport: StubTransport(log: log) { request in
            if await attempt.next() == 1 { throw URLError(.notConnectedToInternet) }
            return (try Fixture.data("search_page_last"), .stub(200, for: request))
        })
        let page = try Fixture.decode(SearchPage.self, from: "search_page")
        let pager = ResultsPager(client: client, firstPage: page)

        await #expect(throws: ScryboardError.self) { _ = try await pager.loadMore() }
        #expect(await pager.lastFailure != nil)
        #expect(await pager.cards.count == 2)
        #expect(await pager.canLoadMore, "a failed fetch must not lose the cursor")

        #expect(try await pager.retry())
        #expect(await pager.lastFailure == nil)
        #expect(await pager.cards.count == 3)
    }

    @Test("Scroll-driven prefetching swallows the error rather than throwing")
    func prefetchDoesNotThrow() async throws {
        let client = ScryfallClient(transport: StubTransport(failure: .notConnectedToInternet))
        let page = try Fixture.decode(SearchPage.self, from: "search_page")
        let pager = ResultsPager(client: client, firstPage: page, prefetchDistance: 4)

        await pager.cardAppeared(at: 1)

        #expect(await pager.lastFailure == .transport(.offline, message: URLError(.notConnectedToInternet).localizedDescription))
        #expect(await pager.isLoadingMore == false)
    }
}

/// Counts calls across concurrent transport invocations.
actor Counter {
    private var count = 0

    func next() -> Int {
        count += 1
        return count
    }
}
