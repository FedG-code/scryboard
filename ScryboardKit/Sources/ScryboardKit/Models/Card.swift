import Foundation

/// A Scryfall card object.
///
/// Only the fields Scryboard needs are modelled; unknown keys in the response are
/// ignored, so new Scryfall fields never break decoding.
public struct Card: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let oracleID: UUID?
    public let name: String
    public let layout: Layout
    public let manaCost: String?
    public let typeLine: String?
    public let oracleText: String?
    public let setCode: String
    public let setName: String?
    public let collectorNumber: String
    public let releasedAt: String?
    public let scryfallURI: URL?
    /// Present for single-faced layouts, and for layouts whose faces share one
    /// piece of artwork (split, flip, adventure). `nil` for transform / modal DFC.
    public let imageURIs: ImageURIs?
    /// Present for every multi-faced layout, including the ones that share artwork.
    public let cardFaces: [CardFace]?

    private enum CodingKeys: String, CodingKey {
        case id
        case oracleID = "oracle_id"
        case name
        case layout
        case manaCost = "mana_cost"
        case typeLine = "type_line"
        case oracleText = "oracle_text"
        case setCode = "set"
        case setName = "set_name"
        case collectorNumber = "collector_number"
        case releasedAt = "released_at"
        case scryfallURI = "scryfall_uri"
        case imageURIs = "image_uris"
        case cardFaces = "card_faces"
    }

    public init(
        id: UUID,
        oracleID: UUID? = nil,
        name: String,
        layout: Layout = .normal,
        manaCost: String? = nil,
        typeLine: String? = nil,
        oracleText: String? = nil,
        setCode: String,
        setName: String? = nil,
        collectorNumber: String,
        releasedAt: String? = nil,
        scryfallURI: URL? = nil,
        imageURIs: ImageURIs? = nil,
        cardFaces: [CardFace]? = nil
    ) {
        self.id = id
        self.oracleID = oracleID
        self.name = name
        self.layout = layout
        self.manaCost = manaCost
        self.typeLine = typeLine
        self.oracleText = oracleText
        self.setCode = setCode
        self.setName = setName
        self.collectorNumber = collectorNumber
        self.releasedAt = releasedAt
        self.scryfallURI = scryfallURI
        self.imageURIs = imageURIs
        self.cardFaces = cardFaces
    }

    // MARK: - Image access

    /// The image set to show for this card, wherever Scryfall happened to put it.
    ///
    /// This is the uniform accessor the UI uses: single-faced cards answer with
    /// their own `image_uris`, double-faced cards with the front face's.
    public var frontImageURIs: ImageURIs? {
        imageURIs ?? cardFaces?.first?.imageURIs
    }

    /// Front-face URL at the requested size. The grid asks for `.small`, the
    /// pasteboard copy for `.normal`.
    public func imageURL(_ size: ImageSize) -> URL? {
        frontImageURIs?[size]
    }

    /// Image set for a given face index, falling back to the card's own images
    /// for layouts whose faces share one scan (split, flip, adventure).
    public func imageURIs(forFace index: Int) -> ImageURIs? {
        guard let cardFaces, cardFaces.indices.contains(index) else {
            return index == 0 ? imageURIs : nil
        }
        return cardFaces[index].imageURIs ?? imageURIs
    }

    /// `true` when the card has two or more faces that each carry their own
    /// artwork — i.e. when a flip affordance in the UI is meaningful.
    ///
    /// Deliberately driven by the payload rather than by ``layout``, so new
    /// double-faced layouts work without a code change.
    public var hasDistinctFaceImages: Bool {
        guard let cardFaces, cardFaces.count > 1 else { return false }
        return cardFaces.allSatisfy { $0.imageURIs != nil }
    }
}
