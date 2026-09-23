import Foundation
import ScryboardKit

/// How big the grid draws each card. Chosen in the container app or by
/// pinching the grid; the keyboard's height never changes, only the columns.
public enum CardSize: String, Sendable, Hashable, CaseIterable, Codable {
    case small, medium, large

    public var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    /// The cell width the grid aims for, in points. Columns are whatever
    /// number of these fit: on a phone 4, 3 and 2.
    public var targetCellWidth: Double {
        switch self {
        case .small: 88
        case .medium: 118
        case .large: 172
        }
    }

    public var larger: CardSize? {
        switch self {
        case .small: .medium
        case .medium: .large
        case .large: nil
        }
    }

    public var smaller: CardSize? {
        switch self {
        case .small: nil
        case .medium: .small
        case .large: .medium
        }
    }
}

/// What tapping a card puts on the pasteboard.
public enum CopyFormat: String, Sendable, Hashable, CaseIterable, Codable {
    /// The `normal` scan as a JPEG. The product's reason to exist.
    case image
    /// The card's page on scryfall.com, which chat apps unfurl into a preview.
    case link
    /// The card's name; from the printings view, a decklist line naming the
    /// printing (see `Card.decklistLine`).
    case text

    public var title: String {
        switch self {
        case .image: "Image"
        case .link: "Scryfall link"
        case .text: "Text"
        }
    }
}

/// What the user set in the container app. Read by the extension on every
/// appearance, so a change in the app shows the next time the keyboard opens.
public struct Preferences: Sendable, Hashable, Codable {
    /// Sort for typed searches. The empty grid keeps its own default.
    public var order: SearchOrder
    public var direction: SortDirection
    public var cardSize: CardSize
    public var copyFormat: CopyFormat

    public init(
        order: SearchOrder = .edhrec,
        direction: SortDirection = .auto,
        cardSize: CardSize = .medium,
        copyFormat: CopyFormat = .image
    ) {
        self.order = order
        self.direction = direction
        self.cardSize = cardSize
        self.copyFormat = copyFormat
    }

    /// Every field falls back to its default when missing, so preferences
    /// saved by an older build survive a new field being added rather than
    /// resetting the lot.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Preferences()
        order = try container.decodeIfPresent(SearchOrder.self, forKey: .order) ?? defaults.order
        direction = try container.decodeIfPresent(SortDirection.self, forKey: .direction) ?? defaults.direction
        cardSize = try container.decodeIfPresent(CardSize.self, forKey: .cardSize) ?? defaults.cardSize
        copyFormat = try container.decodeIfPresent(CopyFormat.self, forKey: .copyFormat) ?? defaults.copyFormat
    }
}

/// Stores ``Preferences`` in the App Group's defaults, which both the app and
/// the extension can read. Falls back to the process's own defaults if the
/// entitlement is missing, so a build without the group still runs (settings
/// then just do not cross over).
// `UserDefaults` is documented thread-safe but not marked Sendable.
public final class PreferencesStore: @unchecked Sendable {
    public static let appGroup = "group.com.fedg.scryboard"
    public static let shared = PreferencesStore()

    private let defaults: UserDefaults
    private let key = "preferences"

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: PreferencesStore.appGroup) ?? .standard
    }

    public func load() -> Preferences {
        guard let data = defaults.data(forKey: key),
              let preferences = try? JSONDecoder().decode(Preferences.self, from: data)
        else { return Preferences() }
        return preferences
    }

    public func save(_ preferences: Preferences) {
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: key)
        }
    }
}
