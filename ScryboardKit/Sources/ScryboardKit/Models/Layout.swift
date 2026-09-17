import Foundation

/// A card's `layout`, modelled as an open string wrapper rather than a closed
/// enum: Scryfall adds layouts whenever Wizards prints something new, and an
/// unknown value must not fail decoding.
public struct Layout: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public static let normal: Layout = "normal"
    public static let split: Layout = "split"
    public static let flip: Layout = "flip"
    public static let transform: Layout = "transform"
    public static let modalDFC: Layout = "modal_dfc"
    public static let meld: Layout = "meld"
    public static let leveler: Layout = "leveler"
    public static let saga: Layout = "saga"
    public static let adventure: Layout = "adventure"
    public static let token: Layout = "token"
    public static let reversibleCard: Layout = "reversible_card"
    public static let artSeries: Layout = "art_series"
}
