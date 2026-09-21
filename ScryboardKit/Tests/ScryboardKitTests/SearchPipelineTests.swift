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

    // MARK: Typing

    @Test("Typing plain text suggests card names")
    func plainTextCompletes() async throws {
        let log = RequestLog()
        let pipeline = makePipeline(log: log)

        await pipeline.typed("lightning")
        let outcomes = await pipeline.take(1)

        guard case .names(let names, let query) = outcomes[0] else {
            Issue.record("expected names, got \(outcomes[0])")
            return
        }
        #expect(query == "lightning")
        #expect(names.first == "Lightning Bolt")
        #expect(await log.paths == ["/cards/autocomplete"])
    }

    /// Nothing card-shaped is on screen while the user types, so a search per
    /// keystroke would be requests the user never sees.
    @Test("Typing syntax clears the strip and sends nothing")
    func syntaxWhileTypingIsLocal() async throws {
        let log = RequestLog()
        let pipeline = makePipeline(log: log)

        await pipeline.typed("otag:removal")
        let outcomes = await pipeline.take(1)

        #expect(outcomes == [.names([], query: "otag:removal")])
        #expect(await log.count == 0)
    }

    /// The whole point: a burst of keystrokes must cost one request, not one per
    /// character.
    @Test("A burst of keystrokes costs a single request")
    func rapidTypingCollapses() async throws {
        let log = RequestLog()
        let pipeline = makePipeline(log: log)

        for prefix in ["l", "li", "lig", "ligh", "light", "lightn", "lightni", "lightning"] {
            await pipeline.typed(prefix)
        }
        let outcomes = await pipeline.take(1)

        #expect(outcomes[0].query == "lightning")
        #expect(await log.count == 1, "only the settled query should reach the network")
        #expect(await log.last?.queryValue("q") == "lightning")
    }

    @Test("Superseded keystrokes emit nothing at all")
    func supersededQueriesAreSilent() async throws {
        let pipeline = makePipeline()

        await pipeline.typed("counterspell")
        await pipeline.typed("lightning")
        let outcomes = await pipeline.take(1)

        #expect(outcomes.count == 1)
        #expect(outcomes[0].query == "lightning")
        if case .names(let names, _) = outcomes[0] {
            #expect(names.first == "Lightning Bolt")
        } else {
            Issue.record("expected names, got \(outcomes[0])")
        }
    }

    @Test("Clearing the search bar reports idle without a request")
    func emptyQueryIsIdle() async throws {
        let log = RequestLog()
        let pipeline = makePipeline(log: log)

        await pipeline.typed("")
        await pipeline.typed("   ")
        let outcomes = await pipeline.take(2)

        #expect(outcomes == [.idle, .idle])
        #expect(await log.count == 0)
    }

    @Test("Clearing the bar cancels the suggestion that was pending")
    func clearingCancelsInFlight() async throws {
        let pipeline = makePipeline()

        await pipeline.typed("lightning")
        await pipeline.typed("")
        let outcomes = await pipeline.take(1)

        #expect(outcomes == [.idle])
    }

    @Test("cancel() drops the pending suggestion")
    func explicitCancel() async throws {
        let log = RequestLog()
        let pipeline = makePipeline(log: log)

        await pipeline.typed("lightning")
        await pipeline.cancel()
        let outcomes = await pipeline.take(1)

        #expect(outcomes == [.idle])
        #expect(await log.count == 0, "cancelled inside the debounce window")
    }

    @Test("A one-character query stays local and clears the strip")
    func shortQueryYieldsNoNames() async throws {
        let log = RequestLog()
        let pipeline = makePipeline(log: log)

        await pipeline.typed("l")
        let outcomes = await pipeline.take(1)

        #expect(outcomes == [.names([], query: "l")])
        #expect(await log.count == 0)
    }

    @Test("No suggestions clears the strip rather than showing an empty state")
    func noSuggestionsClearsStrip() async throws {
        let pipeline = makePipeline { request in
            (try Fixture.data("autocomplete_empty"), .stub(200, for: request))
        }

        await pipeline.typed("zzzzzz")
        let outcomes = await pipeline.take(1)

        #expect(outcomes == [.names([], query: "zzzzzz")])
    }

    /// The strip is a convenience. If it cannot be filled the user still has
    /// the Search key, and that path does report what went wrong.
    @Test("A failed suggestion request is silent")
    func suggestionFailuresAreSilent() async throws {
        let pipeline = SearchPipeline(
            client: ScryfallClient(transport: StubTransport(failure: .notConnectedToInternet)),
            sleep: instantSleeper
        )

        await pipeline.typed("lightning")
        let outcomes = await pipeline.take(1)

        #expect(outcomes == [.names([], query: "lightning")])
    }

    // MARK: Committing

    @Test("Search runs the query as typed and reports cards")
    func searchReportsCards() async throws {
        let log = RequestLog()
        let pipeline = makePipeline(log: log)

        await pipeline.search("otag:removal")
        let outcomes = await pipeline.take(2)

        #expect(outcomes[0] == .loading(query: "otag:removal"))
        guard case .cards(let page, let query) = outcomes[1] else {
            Issue.record("expected cards, got \(outcomes[1])")
            return
        }
        #expect(query == "otag:removal")
        #expect(page.data.count == 2)
        #expect(await log.paths == ["/cards/search"])
        #expect(await log.last?.queryValue("q") == "otag:removal")
        #expect(await log.last?.queryValue("unique") == "cards")
    }

    /// Scryfall matches bare words against names, so plain text is searched
    /// verbatim rather than translated into syntax.
    @Test("Plain text is searched as-is")
    func plainTextSearchesVerbatim() async throws {
        let log = RequestLog()
        let pipeline = makePipeline(log: log)

        await pipeline.search("lightning")
        _ = await pipeline.take(2)

        #expect(await log.paths == ["/cards/search"])
        #expect(await log.last?.queryValue("q") == "lightning")
    }

    @Test("An exact-name search asks for every printing, newest first")
    func exactNameSearchesPrintings() async throws {
        let log = RequestLog()
        let pipeline = makePipeline(log: log)

        await pipeline.searchExact(name: "Lightning Bolt")
        let outcomes = await pipeline.take(2)

        #expect(outcomes[0] == .loading(query: "!\"Lightning Bolt\""))
        #expect(await log.last?.queryValue("q") == "!\"Lightning Bolt\"")
        #expect(await log.last?.queryValue("unique") == "prints")
        #expect(await log.last?.queryValue("order") == "released")
        #expect(await log.last?.queryValue("dir") == "desc")
    }

    @Test("Searching cancels a pending suggestion")
    func searchCancelsPendingSuggestion() async throws {
        let log = RequestLog()
        let pipeline = makePipeline(log: log)

        await pipeline.typed("lightning")
        await pipeline.search("lightning")
        let outcomes = await pipeline.take(2)

        #expect(outcomes[0] == .loading(query: "lightning"))
        #expect(outcomes[1].query == "lightning")
        if case .names = outcomes[1] { Issue.record("the pending suggestion should have been cancelled") }
        #expect(await log.paths == ["/cards/search"])
    }

    @Test("A newer search supersedes the one in flight")
    func newerSearchSupersedes() async throws {
        let pipeline = makePipeline()

        await pipeline.search("t:goblin")
        await pipeline.search("t:elf")
        let outcomes = await pipeline.take(3)

        // Two loading events are expected; only the newer query settles.
        #expect(outcomes[0] == .loading(query: "t:goblin"))
        #expect(outcomes[1] == .loading(query: "t:elf"))
        #expect(outcomes[2].query == "t:elf")
        if case .loading = outcomes[2] { Issue.record("expected the newer search to settle") }
    }

    @Test("Searching an empty bar reports idle without a request")
    func emptySearchIsIdle() async throws {
        let log = RequestLog()
        let pipeline = makePipeline(log: log)

        await pipeline.search("  ")
        let outcomes = await pipeline.take(1)

        #expect(outcomes == [.idle])
        #expect(await log.count == 0)
    }

    @Test("Queries are trimmed before they are sent")
    func trimsBeforeSending() async throws {
        let log = RequestLog()
        let pipeline = makePipeline(log: log)

        await pipeline.typed("   lightning   ")
        #expect(await pipeline.take(1)[0].query == "lightning")
        #expect(await log.last?.queryValue("q") == "lightning")

        await pipeline.search("   otag:removal   ")
        #expect(await pipeline.take(2)[1].query == "otag:removal")
        #expect(await log.last?.queryValue("q") == "otag:removal")
    }

    @Test("A malformed query is reported, not swallowed")
    func failuresSurface() async throws {
        let pipeline = makePipeline { request in
            (try Fixture.data("error_bad_request"), .stub(400, for: request))
        }

        await pipeline.search("frobnicate:yes")
        let outcomes = await pipeline.take(2)

        guard case .failure(let error, let query) = outcomes[1] else {
            Issue.record("expected a failure, got \(outcomes[1])")
            return
        }
        #expect(query == "frobnicate:yes")
        #expect(error.scryfallError?.code == "bad_request")
        #expect(error.isNotFound == false)
    }

    @Test("Being offline is reported as a transport failure")
    func offlineSurfaces() async throws {
        let pipeline = SearchPipeline(
            client: ScryfallClient(transport: StubTransport(failure: .notConnectedToInternet)),
            sleep: instantSleeper
        )

        await pipeline.search("otag:removal")
        let outcomes = await pipeline.take(2)

        #expect(outcomes[1] == .failure(.transport(.offline, message: URLError(.notConnectedToInternet).localizedDescription), query: "otag:removal"))
    }

    /// Scryfall answers a search that matched nothing with a 404. Surfacing that
    /// as a failure would tell the user something went wrong when it did not.
    @Test("A search that matches nothing is an empty state, not a failure")
    func noMatchesIsEmptyNotFailure() async throws {
        let pipeline = makePipeline { request in
            (try Fixture.data("error_not_found"), .stub(404, for: request))
        }

        await pipeline.search("otag:frobnicate")
        let outcomes = await pipeline.take(2)

        #expect(outcomes[1] == .empty(query: "otag:frobnicate"))
    }

    @Test("A page with no cards is an empty state")
    func emptyPageIsEmpty() async throws {
        let pipeline = makePipeline { request in
            (Data(#"{"object":"list","total_cards":0,"has_more":false,"data":[]}"#.utf8),
             .stub(200, for: request))
        }

        await pipeline.search("otag:removal")
        let outcomes = await pipeline.take(2)

        #expect(outcomes[1] == .empty(query: "otag:removal"))
    }

    /// An empty result and a broken connection must not look the same to the UI.
    @Test("Empty and offline are distinguishable")
    func emptyIsNotOffline() async throws {
        #expect(SearchOutcome.empty(query: "x").query == "x")
        #expect(SearchOutcome.empty(query: "x") != .failure(.transport(.offline, message: ""), query: "x"))
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
    /// delay is known to be wired up rather than merely injected.
    @Test("The default delay debounces against the real clock")
    func realClockDebounce() async throws {
        let log = RequestLog()
        let transport = StubTransport(log: log, fixture: "autocomplete")
        let pipeline = SearchPipeline(
            client: ScryfallClient(transport: transport),
            autocompleteDelay: .milliseconds(40)
        )

        for prefix in ["l", "li", "lig", "lightning"] {
            await pipeline.typed(prefix)
        }
        let outcomes = await pipeline.take(1)

        #expect(outcomes[0].query == "lightning")
        #expect(await log.count == 1)
    }
}
