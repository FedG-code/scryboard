import Foundation

/// One face of a multi-faced card (`card_faces[n]`).
///
/// Transform and modal double-faced layouts give every face its own `image_uris`.
/// Split, flip and adventure layouts have faces too, but their artwork lives in
/// the card's top-level `image_uris` — see ``Card/hasDistinctFaceImages``.
public struct CardFace: Codable, Hashable, Sendable {
    public let name: String
    public let manaCost: String?
    public let typeLine: String?
    public let oracleText: String?
    public let imageURIs: ImageURIs?

    private enum CodingKeys: String, CodingKey {
        case name
        case manaCost = "mana_cost"
        case typeLine = "type_line"
        case oracleText = "oracle_text"
        case imageURIs = "image_uris"
    }

    public init(
        name: String,
        manaCost: String? = nil,
        typeLine: String? = nil,
        oracleText: String? = nil,
        imageURIs: ImageURIs? = nil
    ) {
        self.name = name
        self.manaCost = manaCost
        self.typeLine = typeLine
        self.oracleText = oracleText
        self.imageURIs = imageURIs
    }
}
