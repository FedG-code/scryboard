import Foundation
import ImageIO
import CoreGraphics

/// Decodes an image at no more than a given pixel size.
///
/// The keyboard extension has a hard memory ceiling and iOS kills it silently
/// when crossed. Decoding a JPEG with `UIImage(data:)` and then shrinking it
/// costs the full-size bitmap first; ImageIO's thumbnail path decodes straight
/// to the target size and never materialises the large one.
public enum ImageDownsampler {
    public enum Failure: Error, Equatable {
        case unreadable
    }

    /// - Parameter maxPixelSize: the longer edge of the result, in pixels.
    ///   A source smaller than this is decoded at its own size, never enlarged.
    public static func downsample(_ data: Data, maxPixelSize: Int) throws -> CGImage {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            throw Failure.unreadable
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            throw Failure.unreadable
        }
        return image
    }
}
