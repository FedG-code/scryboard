import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The seam that keeps the test suite off the network.
///
/// ``ScryfallClient`` never touches `URLSession` directly; it sends every request
/// through this protocol, so tests inject canned responses and the suite runs
/// with `swift test` alone — no simulator, no network.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The live transport. Cancellation propagates as `CancellationError`, so a
/// superseded search unwinds quietly.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// A session tuned for a keyboard extension: no disk cache (the extension's
    /// memory ceiling is tight and card JSON is small), short timeouts, and
    /// requests that fail fast rather than waiting for connectivity — the user
    /// is typing and wants an answer or an error, not a stall.
    public static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ScryboardError.transport(.other, message: "Response was not HTTP.")
        }
        return (data, http)
    }
}
