import Foundation

/// The image sizes Scryfall publishes for a card or card face.
///
/// Scryboard uses `small` for grid thumbnails and `normal` for the pasteboard copy;
/// the rest are modelled so the type stays faithful to the API.
public enum ImageSize: String, Sendable, Hashable, CaseIterable {
    /// 146 × 204 JPG — grid thumbnails.
    case small
    /// 488 × 680 JPG — what gets written to the pasteboard.
    case normal
    /// 672 × 936 JPG.
    case large
    /// 745 × 1040 PNG with a transparent rounded corner.
    case png
    /// Just the illustration, no frame. Never used: cropping art away from its
    /// attribution is forbidden by the Fan Content Policy.
    case artCrop = "art_crop"
    /// Full card with the border cropped off.
    case borderCrop = "border_crop"
}

/// The `image_uris` object attached to a card, or to a single face of a
/// multi-faced card.
public struct ImageURIs: Codable, Hashable, Sendable {
    public let small: URL?
    public let normal: URL?
    public let large: URL?
    public let png: URL?
    public let artCrop: URL?
    public let borderCrop: URL?

    private enum CodingKeys: String, CodingKey {
        case small, normal, large, png
        case artCrop = "art_crop"
        case borderCrop = "border_crop"
    }

    public init(
        small: URL? = nil,
        normal: URL? = nil,
        large: URL? = nil,
        png: URL? = nil,
        artCrop: URL? = nil,
        borderCrop: URL? = nil
    ) {
        self.small = small
        self.normal = normal
        self.large = large
        self.png = png
        self.artCrop = artCrop
        self.borderCrop = borderCrop
    }

    public subscript(size: ImageSize) -> URL? {
        switch size {
        case .small: small
        case .normal: normal
        case .large: large
        case .png: png
        case .artCrop: artCrop
        case .borderCrop: borderCrop
        }
    }
}
