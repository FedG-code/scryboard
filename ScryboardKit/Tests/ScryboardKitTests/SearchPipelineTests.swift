import Foundation
import Testing
@testable import ScryboardKit

/// The pipeline is what keeps Scryboard under Scryfall's rate limit, so these
/// tests are about *how many* requests leave the device as much as about results.
@Suite("Search pipeline", .timeLimit(.minutes(1)))
struct SearchPipelineTests {
    private func makePipeline(
        log: RequestLog = RequestLog(),
        handler: (@Sendable (URLRequest) async throws -> (Data, HTTPURLResponse))? = nil
    ) -> SearchPipeline {
        let transport = StubTransport(log: log, handler: handler ?? { request in
            let fixture = request.url?.path == "/cards/autocomplete" ? "autocomplete" : "search_page"
            return (try Fixture.data(fixture), .stub(200, for: request))
        })
        return SearchPipeline(
            client: ScryfallClient(transport: transport),
            sleep: instantSleeper
        )
    }

    @Test("Plain text is completed as a name")
    func plainTextCompletes() async throws {
        let log = RequestLog()
        let pipeline = makePipeline(log: log)

        await pipeline.submit("lightning")
        let outcomes = await pipeline.take(2)

        #expect(outcomes[0] == .loading(query: "lightning"))
        guard case .names(let names, let query) = outcomes[1] else {
            Issue.record("expected names, got \(outcomes[1])")
            return
        }
        #expect(query == "lightning")
        #expect(names.first == "Lightning Bolt")
        #expect(await log.paths == ["/cards/autocomplete"])
    }

    @Test("Syntax goes to the search endpoint")
    func syntaxSearches() async throws {
        let log = RequestLog()
        let pipeline = makePipeline(log: log)

        await pipeline.submit("otag:removal")
        let outcomes = await pipeline.take(2)

        guard case .cards(let page, let query) = outcomes[1] else {
            Issue.record("expected cards, got \(outcomes[1])")
            return
        }
        #expect(query == "otag:removal")
        #expect(page.data.count == 2)
        #expect(await log.paths == ["/cards/search"])
        #expect(await log.last?.queryValue("q") == "otag:removal")
    }

    /// The whole point: a burst of keystrokes must cost one request, not one per
    /// character.
    @Test("A burst of keystrokes costs a single request")
    func rapidTypingCollapses() async throws {
        let log = RequestLog()
        let pipeline = makePipeline(log: log)

        for prefix in ["l", "li", "lig", "ligh", "light", "lightn", "lightni", "lightning"] {
            await pipeline.submit(prefix)
        }
        let outcomes = await pipeline.take(2)

        #expect(outcomes[0] == .loading(query: "lightning"))
        #expect(outcomes[1].query == "lightning")
        #expect(await log.count == 1, "only the settled query should reach the network")
        #expect(await log.last?.queryValue("q") == "lightning")
    }

    @Test("Superseded queries emit nothing at all")
    func supersededQueriesAreSilent() async throws {
        let pipeline = makePipeline()

        await pipeline.submit("counterspell")
        await pipeline.submit("lightning")
        let outcomes = await pipeline.take(2)

        #expect(outcomes.allSatisfy { $0.query == "lightning" })
        #expect(outcomes.contains { $0.query == "counterspell" } == false)
    }

    @Test("Clearing the search bar reports idle without a request")
    func emptyQueryIsIdle() async throws {
        let log = RequestLog()
        let pipeline = makePipeline(log: log)

        await pipeline.submit("")
        await pipeline.submit("   ")
        let outcomes = await pipeline.take(2)

        #expect(outcomes == [.idle, .idle])
        #expect(await log.count == 0)
    }

    @Test("Clearing the bar cancels the query that was in flight")
    func clearingCancelsInFlight() async throws {
        let pipeline = makePipeline()

        await pipeline.submit("lightning")
        await pipeline.submit("")
        let outcomes = await pipeline.take(1)

        #expect(outcomes == [.idle])
    }

    @Test("cancel() drops the pending query")
    func explicitCancel() async throws {
        let log = RequestLog()
        let pipeline = makePipeline(log: log)

        await pipeline.submit("lightning")
        await pipeline.cancel()
        let outcomes = await pipeline.take(1)

        #expect(outcomes == [.idle])
        #expect(await log.count == 0, "cancelled inside the debounce window")
    }

    @Test("Queries are trimmed before they are classified and sent")
    func trimsBeforeRouting() async throws {
        let log = RequestLog()
        let pipeline = makePipeline(log: log)

        await pipeline.submit("   lightning   ")
        let outcomes = await pipeline.take(2)

        #expect(outcomes[1].query == "lightning")
        #expect(await log.last?.queryValue("q") == "lightning")
    }

    @Test("A Scryfall error is reported, not swallowed")
    func failuresSurface() async throws {
        let pipeline = makePipeline { request in
            (try Fixture.data("error_not_found"), .stub(404, for: request))
        }

        await pipeline.submit("otag:frobnicate")
        let outcomes = await pipeline.take(2)

        guard case .failure(let error, let query) = outcomes[1] else {
            Issue.record("expected a failure, got \(outcomes[1])")
            return
        }
        #expect(query == "otag:frobnicate")
        #expect(error.isNotFound)
    }

    @Test("Being offline is reported as a transport failure")
    func offlineSurfaces() async throws {
        let pipeline = SearchPipeline(
            client: ScryfallClient(transport: StubTransport(failure: .notConnectedToInternet)),
            sleep: instantSleeper
        )

        await pipeline.submit("otag:removal")
        let outcomes = await pipeline.take(2)

        #expect(outcomes[1] == .failure(.transport(.offline, message: URLError(.notConnectedToInternet).localizedDescription), query: "otag:removal"))
    }

    @Test("A one-character query stays local but still settles")
    func shortQueryYieldsNoNames() async throws {
        let log = RequestLog()
        let pipeline = makePipeline(log: log)

        await pipeline.submit("l")
        let outcomes = await pipeline.take(2)

        #expect(outcomes[0] == .loading(query: "l"))
        #expect(outcomes[1] == .names([], query: "l"))
        #expect(await log.count == 0)
    }

    @Test("finish() closes the stream")
    func finishClosesStream() async throws {
        let pipeline = makePipeline()
        await pipeline.finish()

        var received: [SearchOutcome] = []
        for await outcome in pipeline.outcomes {
            received.append(outcome)
        }
        #expect(received.isEmpty)
    }

    /// The real debounce, exercised once against the wall clock so the default
    /// delays are known to be wired up rather than merely injected.
    @Test("The default delays debounce against the real clock")
    func realClockDebounce() async throws {
        let log = RequestLog()
        let transport = StubTransport(log: log, fixture: "autocomplete")
        let pipeline = SearchPipeline(
            client: ScryfallClient(transport: transport),
            autocompleteDelay: .milliseconds(40),
            searchDelay: .milliseconds(40)
        )

        for prefix in ["l", "li", "lig", "lightning"] {
            await pipeline.submit(prefix)
        }
        let outcomes = await pipeline.take(2)

        #expect(outcomes[1].query == "lightning")
        #expect(await log.count == 1)
    }
}
