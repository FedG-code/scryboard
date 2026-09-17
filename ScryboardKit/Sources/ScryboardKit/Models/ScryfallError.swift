import Foundation

/// Scryfall's own error object: an HTTP 4xx/5xx response whose body is
/// `{"object":"error", ...}`.
///
/// This is a well-formed answer from a healthy API, not a malfunction — a 404
/// from `/cards/named` means "no such card" and a 404 from `/cards/search` means
/// "nothing matched". Kept distinct from transport failures for that reason.
public struct ScryfallError: Codable, Hashable, Sendable {
    /// The HTTP status Scryfall reported in the body.
    public let status: Int
    /// Machine-readable slug, e.g. `not_found`, `bad_request`.
    public let code: String
    /// Human-readable explanation, safe to show to the user.
    public let details: String
    /// Present on `bad_request` for malformed search syntax.
    public let type: String?
    public let warnings: [String]?

    public init(
        status: Int,
        code: String,
        details: String,
        type: String? = nil,
        warnings: [String]? = nil
    ) {
        self.status = status
        self.code = code
        self.details = details
        self.type = type
        self.warnings = warnings
    }

    /// `true` when the query was well-formed but matched nothing.
    public var isNotFound: Bool { status == 404 }
}

/// Why a network transport attempt never produced an HTTP response.
///
/// Coarse on purpose: the UI only needs to tell "you're offline" apart from
/// "something else went wrong", and this maps cleanly onto the Kotlin port.
public enum TransportFailure: String, Sendable, Hashable {
    case offline
    case timedOut
    case other
}

/// Everything ``ScryfallClient`` can throw, apart from `CancellationError`.
///
/// Cancellation is not represented here: a superseded request throws
/// `CancellationError` so callers can ignore it without pattern-matching a
/// failure case.
public enum ScryboardError: Error, Sendable, Hashable {
    /// Scryfall answered with its structured error object.
    case scryfall(ScryfallError)
    /// The request never reached Scryfall, or the response never arrived.
    case transport(TransportFailure, message: String)
    /// A 2xx body that did not match the expected shape.
    case decoding(message: String)
    /// A non-2xx response whose body was not a Scryfall error object.
    case unexpectedStatus(code: Int)
    /// A query that could not be turned into a valid URL.
    case invalidURL(String)

    /// The Scryfall error object, when this failure carries one.
    public var scryfallError: ScryfallError? {
        if case .scryfall(let error) = self { return error }
        return nil
    }

    /// `true` when the query was valid but matched no cards.
    public var isNotFound: Bool {
        scryfallError?.isNotFound ?? false
    }
}

extension ScryboardError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .scryfall(let error):
            error.details
        case .transport(.offline, _):
            "No internet connection."
        case .transport(.timedOut, _):
            "The request timed out."
        case .transport(.other, let message):
            message
        case .decoding(let message):
            "Unexpected response from Scryfall: \(message)"
        case .unexpectedStatus(let code):
            "Scryfall returned HTTP \(code)."
        case .invalidURL(let query):
            "Could not build a request for \"\(query)\"."
        }
    }
}
