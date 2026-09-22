import Foundation
import CoreGraphics

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fetches card images and hands back decoded thumbnails, with the two caches
/// the memory ceiling calls for: bytes on disk via `URLCache`, decoded bitmaps
/// in a bounded `NSCache`.
///
/// One instance per process. Thumbnails are decoded at the requested pixel
/// size, which the grid caps at its cell, and the cache's cost limit bounds
/// the total whatever scan they came from.
public actor ImageStore {
    public static let shared = ImageStore()

    private let session: URLSession
    private let thumbnails = NSCache<NSURL, CGImageBox>()
    private var inFlight: [URL: Task<CGImage, Error>] = [:]

    public init(session: URLSession? = nil) {
        self.session = session ?? ImageStore.makeSession()
        thumbnails.countLimit = 150
        // Roughly 150 small scans; NSCache evicts under memory pressure anyway.
        thumbnails.totalCostLimit = 24 * 1024 * 1024
    }

    /// A session whose cache lives in the caches directory, which the system
    /// may evict. Card images never change, so cached bytes are always valid.
    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 2 * 1024 * 1024,
            diskCapacity: 100 * 1024 * 1024,
            directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("scryfall-images", isDirectory: true)
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 15
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = ["User-Agent": "Scryboard/1.0 (github.com/FedG-code/scryboard)"]
        return URLSession(configuration: configuration)
    }

    // MARK: - Thumbnails

    /// A decoded thumbnail for the grid, from memory when possible.
    public func thumbnail(for url: URL, maxPixelSize: Int) async throws -> CGImage {
        if let cached = thumbnails.object(forKey: url as NSURL) {
            return cached.image
        }
        if let task = inFlight[url] {
            return try await task.value
        }
        let task = Task<CGImage, Error> { [session] in
            let data = try await ImageStore.fetch(url, session: session)
            let image = try ImageDownsampler.downsample(data, maxPixelSize: maxPixelSize)
            return image
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        let image = try await task.value
        thumbnails.setObject(CGImageBox(image), forKey: url as NSURL, cost: image.bytesPerRow * image.height)
        return image
    }

    // MARK: - Full images

    /// The bytes of a full-size scan, for the pasteboard. Never decoded here:
    /// the caller writes the data and lets go of it.
    public func imageData(for url: URL) async throws -> Data {
        try await ImageStore.fetch(url, session: session)
    }

    private static func fetch(_ url: URL, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

/// `NSCache` wants a class; `CGImage` is one, but boxing keeps the key/value
/// types explicit and lets the cost be attached where the image is stored.
private final class CGImageBox: @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}
