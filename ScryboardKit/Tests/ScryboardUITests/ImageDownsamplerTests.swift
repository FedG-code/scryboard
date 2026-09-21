import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ScryboardUI

@Suite("Image downsampling")
struct ImageDownsamplerTests {
    /// A solid JPEG of the given size, made without any platform image type.
    private func jpeg(width: Int, height: Int) throws -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test("A large scan is decoded no bigger than the requested size")
    func shrinksToFit() throws {
        let data = try jpeg(width: 488, height: 680)
        let image = try ImageDownsampler.downsample(data, maxPixelSize: 204)
        #expect(max(image.width, image.height) <= 204)
        #expect(image.width < image.height, "aspect ratio is kept")
    }

    @Test("A small scan is never enlarged")
    func doesNotEnlarge() throws {
        let data = try jpeg(width: 146, height: 204)
        let image = try ImageDownsampler.downsample(data, maxPixelSize: 600)
        #expect(image.width == 146)
        #expect(image.height == 204)
    }

    @Test("Garbage is reported, not crashed on")
    func rejectsGarbage() {
        #expect(throws: ImageDownsampler.Failure.unreadable) {
            try ImageDownsampler.downsample(Data("not an image".utf8), maxPixelSize: 100)
        }
    }
}
