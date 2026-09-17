import Foundation
import Testing
@testable import ScryboardKit

// MARK: - Fixtures

/// Canned Scryfall payloads, checked into the repo. The suite never touches the
/// network, and these files double as the contract the Kotlin port is written
/// against.
enum Fixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures"
        ) else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        try JSONDecoder().decode(type, from: data(name))
    }

    enum FixtureError: Error, CustomStringConvertible {
        case missing(String)

        var description: String {
            switch self {
            case .missing(let name): "Missing fixture \(name).json"
            }
        }
    }
}

// MARK: - Stub transport

/// Records every request and answers from a caller-supplied handler.
struct StubTransport: HTTPTransport {
    let log: RequestLog
    private let handler: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    init(
        log: RequestLog = RequestLog(),
        handler: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    ) {
        self.log = log
        self.handler = handler
    }

    /// Always answers 200 with the named fixture.
    init(log: RequestLog = RequestLog(), fixture name: String, status: Int = 200) {
        self.init(log: log) { request in
            (try Fixture.data(name), .stub(status, for: request))
        }
    }

    /// Always fails the way a given `URLError` would.
    init(log: RequestLog = RequestLog(), failure code: URLError.Code) {
        self.init(log: log) { _ in throw URLError(code) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        await log.record(request)
        return try await handler(request)
    }
}

/// Serialises access to the recorded requests so tests stay Sendable-clean.
actor RequestLog {
    private(set) var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        requests.append(request)
    }

    var count: Int { requests.count }
    var urls: [URL] { requests.compactMap(\.url) }
    var paths: [String] { urls.map(\.path) }
    var last: URLRequest? { requests.last }
}

/// A transport that parks mid-request until the test cancels it, so the
/// in-flight cancellation path can be exercised without a race.
struct HangingTransport: HTTPTransport {
    let started: Gate

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        await started.open()
        try await Task.sleep(for: .seconds(60))
        throw URLError(.timedOut)
    }
}

/// A one-shot latch: `wait()` returns once anything has called `open()`.
actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        guard !isOpen else { return }
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

extension HTTPURLResponse {
    static func stub(_ status: Int, for request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.scryfall.com")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
    }
}

extension URLRequest {
    /// The query value for `name`, percent-decoded.
    func queryValue(_ name: String) -> String? {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        return components.queryItems?.first { $0.name == name }?.value
    }

    var rawQuery: String? {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        return components.percentEncodedQuery
    }
}

// MARK: - Pipeline helpers

/// A debounce that costs no wall-clock time but still honours cancellation, so
/// the pipeline's timing behaviour can be tested deterministically.
let instantSleeper: @Sendable (Duration) async throws -> Void = { _ in
    for _ in 0..<8 {
        await Task.yield()
        try Task.checkCancellation()
    }
}

extension SearchPipeline {
    /// Collect the next `count` outcomes. Suites that call this carry a
    /// `.timeLimit` trait, so a pipeline that never settles fails the test
    /// rather than hanging the run.
    nonisolated func take(_ count: Int) async -> [SearchOutcome] {
        var collected: [SearchOutcome] = []
        for await outcome in outcomes {
            collected.append(outcome)
            if collected.count == count { break }
        }
        return collected
    }
}
