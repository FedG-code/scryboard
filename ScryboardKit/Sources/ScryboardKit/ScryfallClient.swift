import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A thin, stateless client for the three Scryfall endpoints Scryboard uses.
///
/// Every request — including a `next_page` URL handed back by Scryfall — is
/// built through one path so the mandatory `User-Agent` and `Accept` headers can
/// never be forgotten. Scryfall rejects requests without them.
public struct ScryfallClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://api.scryfall.com")!

    /// Scryfall asks every client to identify itself descriptively.
    public static let defaultUserAgent = "Scryboard/1.0 (github.com/FedG-code/scryboard)"

    private let transport: any HTTPTransport
    private let baseURL: URL
    private let userAgent: String

    public init(
        transport: any HTTPTransport,
        baseURL: URL = ScryfallClient.defaultBaseURL,
        userAgent: String = ScryfallClient.defaultUserAgent
    ) {
        self.transport = transport
        self.baseURL = baseURL
        self.userAgent = userAgent
    }

    /// Convenience initialiser for production use.
    public init(userAgent: String = ScryfallClient.defaultUserAgent) {
        self.init(
            transport: URLSessionTransport(session: URLSessionTransport.makeDefaultSession()),
            userAgent: userAgent
        )
    }

    // MARK: - Endpoints

    /// Name suggestions for a partially typed card name.
    ///
    /// Scryfall ignores inputs shorter than two characters, so we skip the round
    /// trip entirely — free rate-limit headroom while the user types the first
    /// letter.
    public func autocomplete(_ query: String) async throws -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let request = try makeRequest(path: "/cards/autocomplete", query: [URLQueryItem(name: "q", value: trimmed)])
        return try await perform(request, as: Catalog.self).data
    }

    /// Full-syntax search. Scryfall's server evaluates everything — `otag:`,
    /// `is:`, `cmc<=`, colours — so there is nothing to interpret here.
    ///
    /// A query that matches nothing comes back as a 404 ``ScryfallError``, not an
    /// empty page; check ``ScryboardError/isNotFound``.
    public func search(
        _ query: String,
        unique: SearchUniqueness = .cards,
        order: SearchOrder = .name,
        direction: SortDirection = .auto
    ) async throws -> SearchPage {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ScryboardError.invalidURL(query) }
        let request = try makeRequest(path: "/cards/search", query: [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "unique", value: unique.rawValue),
            URLQueryItem(name: "order", value: order.rawValue),
            URLQueryItem(name: "dir", value: direction.rawValue),
        ])
        return try await perform(request, as: SearchPage.self)
    }

    /// Every printing of a card, newest first.
    ///
    /// Commander players care which art they send, so the picker needs the whole
    /// print run rather than the one printing a search happened to surface.
    /// Matched on `oracle_id` — the identifier that is stable across printings —
    /// falling back to an exact name match for the rare card object that arrives
    /// without one.
    public func printings(of card: Card) async throws -> SearchPage {
        try await search(
            ScryfallClient.printingsQuery(for: card),
            unique: .prints,
            order: .released,
            direction: .descending
        )
    }

    static func printingsQuery(for card: Card) -> String {
        if let oracleID = card.oracleID {
            return "oracleid:\(oracleID.uuidString.lowercased())"
        }
        // `!"…"` is Scryfall's exact-name operator. Card names never contain a
        // double quote, so this needs no escaping.
        return "!\"\(card.name)\""
    }

    /// Resolve a single name to a card. A 404 here means "no such card", not a bug.
    public func namedFuzzy(_ name: String) async throws -> Card {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ScryboardError.invalidURL(name) }
        let request = try makeRequest(path: "/cards/named", query: [URLQueryItem(name: "fuzzy", value: trimmed)])
        return try await perform(request, as: Card.self)
    }

    /// Fetch a page from an absolute URL Scryfall supplied.
    public func page(at url: URL) async throws -> SearchPage {
        try await perform(makeRequest(url: url), as: SearchPage.self)
    }

    /// The page after `page`, or `nil` when there is none.
    public func nextPage(after page: SearchPage) async throws -> SearchPage? {
        guard page.hasMore, let next = page.nextPage else { return nil }
        return try await self.page(at: next)
    }

    // MARK: - Request building

    private func makeRequest(path: String, query: [URLQueryItem]) throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw ScryboardError.invalidURL(path)
        }
        components.queryItems = query
        // URLComponents leaves "+" unescaped in a query value, where a server is
        // free to read it as a space. Scryfall queries can contain one (`pow>=+2`),
        // so escape it explicitly.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else {
            throw ScryboardError.invalidURL(query.first?.value ?? path)
        }
        return makeRequest(url: url)
    }

    /// The single place headers are attached. Everything that leaves this type
    /// goes through here.
    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    // MARK: - Execution

    private func perform<Response: Decodable>(
        _ request: URLRequest,
        as type: Response.Type
    ) async throws -> Response {
        try Task.checkCancellation()

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ScryboardError {
            throw error
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw ScryboardError.transport(TransportFailure(error), message: error.localizedDescription)
        } catch {
            throw ScryboardError.transport(.other, message: String(describing: error))
        }

        try Task.checkCancellation()

        // JSONDecoder is a non-Sendable class, so it is built per call rather
        // than stored — this type has to stay Sendable-clean for the extension.
        let decoder = JSONDecoder()

        guard (200..<300).contains(response.statusCode) else {
            if let apiError = try? decoder.decode(ScryfallError.self, from: data) {
                throw ScryboardError.scryfall(apiError)
            }
            throw ScryboardError.unexpectedStatus(code: response.statusCode)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw ScryboardError.decoding(message: String(describing: error))
        }
    }
}

extension TransportFailure {
    init(_ error: URLError) {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .internationalRoamingOff:
            self = .offline
        case .timedOut:
            self = .timedOut
        default:
            self = .other
        }
    }
}
