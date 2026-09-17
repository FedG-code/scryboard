import Foundation
import Testing
@testable import ScryboardKit

@Suite("Request building")
struct RequestBuildingTests {
    /// Scryfall rejects requests that do not identify themselves. Every path out
    /// of the client must carry both headers — including a `next_page` URL that
    /// Scryfall itself supplied.
    @Test("Every request carries the mandatory headers")
    func mandatoryHeaders() async throws {
        let log = RequestLog()
        let client = ScryfallClient(transport: StubTransport(log: log, fixture: "autocomplete"))
        _ = try await client.autocomplete("bolt")

        let searchLog = RequestLog()
        let searchClient = ScryfallClient(
            transport: StubTransport(log: searchLog, fixture: "search_page")
        )
        _ = try await searchClient.search("otag:removal")
        _ = try await searchClient.page(at: URL(string: "https://api.scryfall.com/cards/search?page=2")!)

        let namedLog = RequestLog()
        let namedClient = ScryfallClient(transport: StubTransport(log: namedLog, fixture: "card_normal"))
        _ = try await namedClient.namedFuzzy("lightnig bolt")

        var recorded = await log.requests
        recorded += await searchLog.requests
        recorded += await namedLog.requests

        #expect(recorded.count == 4)
        for request in recorded {
            #expect(request.value(forHTTPHeaderField: "User-Agent") == ScryfallClient.defaultUserAgent)
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(request.httpMethod == "GET")
        }
    }

    @Test("A custom User-Agent is honoured")
    func customUserAgent() async throws {
        let log = RequestLog()
        let client = ScryfallClient(
            transport: StubTransport(log: log, fixture: "autocomplete"),
            userAgent: "Scryboard-Tests/9.9"
        )
        _ = try await client.autocomplete("bolt")

        let request = try #require(await log.last)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Scryboard-Tests/9.9")
    }

    @Test("Each endpoint hits the documented path")
    func endpointPaths() async throws {
        let log = RequestLog()
        let client = ScryfallClient(transport: StubTransport(log: log) { request in
            let path = request.url?.path ?? ""
            let fixture = switch path {
            case "/cards/autocomplete": "autocomplete"
            case "/cards/search": "search_page"
            default: "card_normal"
            }
            return (try Fixture.data(fixture), .stub(200, for: request))
        })

        _ = try await client.autocomplete("bolt")
        _ = try await client.search("otag:removal")
        _ = try await client.namedFuzzy("bolt")

        #expect(await log.paths == ["/cards/autocomplete", "/cards/search", "/cards/named"])
    }

    @Test("Query parameters are named and encoded correctly")
    func queryEncoding() async throws {
        let log = RequestLog()
        let client = ScryfallClient(transport: StubTransport(log: log, fixture: "search_page"))

        _ = try await client.search("otag:removal cmc<=3 c=wu")
        let request = try #require(await log.last)
        #expect(request.queryValue("q") == "otag:removal cmc<=3 c=wu")
        #expect(request.rawQuery?.contains(" ") == false, "spaces must be escaped")
    }

    /// URLComponents leaves "+" alone in a query value, and a server is free to
    /// read an unescaped "+" as a space — which silently changes the query.
    @Test("Plus signs are escaped rather than read as spaces")
    func plusIsEscaped() async throws {
        let log = RequestLog()
        let client = ScryfallClient(transport: StubTransport(log: log, fixture: "search_page"))

        _ = try await client.search("pow>=+2")
        let request = try #require(await log.last)
        #expect(request.rawQuery?.contains("%2B") == true)
        #expect(request.queryValue("q") == "pow>=+2")
    }

    @Test("Input is trimmed before it is sent")
    func trimsInput() async throws {
        let log = RequestLog()
        let client = ScryfallClient(transport: StubTransport(log: log, fixture: "search_page"))

        _ = try await client.search("   t:goblin   ")
        #expect(await log.last?.queryValue("q") == "t:goblin")
    }

    @Test("A fuzzy name lookup uses the fuzzy parameter")
    func fuzzyParameter() async throws {
        let log = RequestLog()
        let client = ScryfallClient(transport: StubTransport(log: log, fixture: "card_normal"))

        _ = try await client.namedFuzzy("lightnig bolt")
        #expect(await log.last?.queryValue("fuzzy") == "lightnig bolt")
    }

    @Test("A custom base URL is respected")
    func customBaseURL() async throws {
        let log = RequestLog()
        let client = ScryfallClient(
            transport: StubTransport(log: log, fixture: "autocomplete"),
            baseURL: URL(string: "https://example.test/api")!
        )
        _ = try await client.autocomplete("bolt")

        let url = try #require(await log.last?.url)
        #expect(url.host == "example.test")
        #expect(url.path == "/api/cards/autocomplete")
    }
}

@Suite("Client responses")
struct ClientResponseTests {
    @Test("Autocomplete returns the catalog's names")
    func autocompleteReturnsNames() async throws {
        let client = ScryfallClient(transport: StubTransport(fixture: "autocomplete"))
        let names = try await client.autocomplete("lightning")

        #expect(names.count == 6)
        #expect(names.first == "Lightning Bolt")
    }

    /// Scryfall ignores one-character input, so the round trip is skipped
    /// entirely — free headroom against the rate limit while the user starts typing.
    @Test("Autocomplete skips the network for input under two characters")
    func autocompleteSkipsShortInput() async throws {
        let log = RequestLog()
        let client = ScryfallClient(transport: StubTransport(log: log, fixture: "autocomplete"))

        for tooShort in ["l", " ", "", " x "] {
            let names = try await client.autocomplete(tooShort)
            #expect(names.isEmpty)
        }
        #expect(await log.count == 0)

        let names = try await client.autocomplete("li")
        #expect(names.isEmpty == false)
        #expect(await log.count == 1)
    }

    @Test("Search returns a decoded page")
    func searchReturnsPage() async throws {
        let client = ScryfallClient(transport: StubTransport(fixture: "search_page"))
        let page = try await client.search("otag:removal")

        #expect(page.data.count == 2)
        #expect(page.hasMore)
        #expect(page.totalCards == 1287)
    }

    @Test("An empty search query never reaches the network")
    func emptySearchThrows() async throws {
        let log = RequestLog()
        let client = ScryfallClient(transport: StubTransport(log: log, fixture: "search_page"))

        await #expect(throws: ScryboardError.invalidURL("   ")) {
            _ = try await client.search("   ")
        }
        #expect(await log.count == 0)
    }

    @Test("Paging follows the cursor Scryfall supplied")
    func nextPageFollowsCursor() async throws {
        let log = RequestLog()
        let client = ScryfallClient(transport: StubTransport(log: log) { request in
            let fixture = request.url?.query?.contains("page=2") == true
                ? "search_page_last"
                : "search_page"
            return (try Fixture.data(fixture), .stub(200, for: request))
        })

        let first = try await client.search("otag:removal")
        let second = try #require(try await client.nextPage(after: first))

        #expect(second.data.map(\.name) == ["Terror"])
        #expect(second.hasMore == false)
        #expect(await log.urls.last?.query?.contains("page=2") == true)
    }

    @Test("Paging stops at the last page")
    func nextPageReturnsNilAtEnd() async throws {
        let log = RequestLog()
        let client = ScryfallClient(transport: StubTransport(log: log, fixture: "search_page_last"))
        let page = try await client.search("t:terror")

        #expect(try await client.nextPage(after: page) == nil)
        #expect(await log.count == 1, "no request for a page that does not exist")
    }
}

@Suite("Client failures")
struct ClientFailureTests {
    /// A query that matches nothing is a 404 with a Scryfall error object. That
    /// is an answer, not a malfunction, and it must not look like a transport bug.
    @Test("A 404 surfaces as a typed Scryfall error")
    func notFoundIsTyped() async throws {
        let client = ScryfallClient(transport: StubTransport(fixture: "error_not_found", status: 404))

        let error = await #expect(throws: ScryboardError.self) {
            _ = try await client.namedFuzzy("frobnicate")
        }
        #expect(error?.isNotFound == true)
        #expect(error?.scryfallError?.code == "not_found")
    }

    @Test("A 400 surfaces Scryfall's syntax warnings")
    func badRequestIsTyped() async throws {
        let client = ScryfallClient(transport: StubTransport(fixture: "error_bad_request", status: 400))

        let error = await #expect(throws: ScryboardError.self) {
            _ = try await client.search("frobnicate:yes")
        }
        #expect(error?.scryfallError?.code == "bad_request")
        #expect(error?.scryfallError?.warnings?.isEmpty == false)
        #expect(error?.isNotFound == false)
    }

    @Test("Being offline is distinguishable from an API error")
    func offlineIsTransportFailure() async throws {
        let client = ScryfallClient(transport: StubTransport(failure: .notConnectedToInternet))

        let error = await #expect(throws: ScryboardError.self) {
            _ = try await client.search("otag:removal")
        }
        guard case .transport(let kind, _) = error else {
            Issue.record("expected a transport failure, got \(String(describing: error))")
            return
        }
        #expect(kind == .offline)
        #expect(error?.scryfallError == nil)
    }

    @Test("A timeout is its own transport failure")
    func timeoutIsTransportFailure() async throws {
        let client = ScryfallClient(transport: StubTransport(failure: .timedOut))

        let error = await #expect(throws: ScryboardError.self) {
            _ = try await client.search("otag:removal")
        }
        guard case .transport(let kind, _) = error else {
            Issue.record("expected a transport failure, got \(String(describing: error))")
            return
        }
        #expect(kind == .timedOut)
    }

    @Test("A non-2xx response without an error body reports its status")
    func unexpectedStatus() async throws {
        let client = ScryfallClient(transport: StubTransport { request in
            (Data("<html>502 Bad Gateway</html>".utf8), .stub(502, for: request))
        })

        await #expect(throws: ScryboardError.unexpectedStatus(code: 502)) {
            _ = try await client.search("otag:removal")
        }
    }

    @Test("A malformed 200 body is a decoding failure, not a crash")
    func malformedBody() async throws {
        let client = ScryfallClient(transport: StubTransport { request in
            (Data(#"{"object":"list","has_more":"yes please"}"#.utf8), .stub(200, for: request))
        })

        let error = await #expect(throws: ScryboardError.self) {
            _ = try await client.search("otag:removal")
        }
        guard case .decoding = error else {
            Issue.record("expected a decoding failure, got \(String(describing: error))")
            return
        }
    }

    /// A superseded request must unwind as `CancellationError`, never as a
    /// `ScryboardError` the UI would show the user.
    @Test("A cancelled request throws CancellationError, not a user-facing error")
    func cancellationIsNotAnError() async throws {
        let client = ScryfallClient(transport: StubTransport(failure: .cancelled))

        await #expect(throws: CancellationError.self) {
            _ = try await client.search("otag:removal")
        }
    }

    @Test("Cancelling mid-flight unwinds as a cancellation")
    func cancelsMidFlight() async throws {
        let started = Gate()
        let client = ScryfallClient(transport: HangingTransport(started: started))

        let task = Task { try await client.search("otag:removal") }
        await started.wait()
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
