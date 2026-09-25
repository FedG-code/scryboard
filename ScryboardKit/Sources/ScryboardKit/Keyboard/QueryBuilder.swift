import Foundation

// The query builder: the screen the keyboard opens on. A beginner picks a
// filter, an operator in words and a value, reads a sentence saying what the
// clause means, and adds it to the search bar. Everything here is pure data
// so the extension only renders it and the Android IME ports it as is.
//
// The operators are words on purpose. On Scryfall `c:rg` means "includes red
// and green" (`>=`) while `id:ub` means "fits within blue and black" (`<=`),
// checked against the API on 2026-09-23; nobody new could guess that, so the
// builder never emits a bare colon for either and always says what it meant.

/// One of the five colours, by the letter Scryfall uses for it.
public enum ManaColour: Character, Sendable, Hashable, CaseIterable, Comparable {
    case white = "w"
    case blue = "u"
    case black = "b"
    case red = "r"
    case green = "g"

    public var name: String {
        switch self {
        case .white: "White"
        case .blue: "Blue"
        case .black: "Black"
        case .red: "Red"
        case .green: "Green"
        }
    }

    /// WUBRG order, which is how Scryfall writes and players read them.
    public static func < (lhs: ManaColour, rhs: ManaColour) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

extension Set<ManaColour> {
    /// The letters in WUBRG order: `ub`, `wubrg`.
    public var letters: String {
        String(sorted().map(\.rawValue))
    }

    /// "Blue and Black (Dimir)". Names in WUBRG order; the nickname when the
    /// combination has one.
    public var description: String {
        let names = sorted().map(\.name)
        var text: String
        switch names.count {
        case 0: text = ""
        case 1: text = names[0]
        default: text = names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
        if let nickname = Self.nicknames[letters] {
            text += " (\(nickname))"
        }
        return text
    }

    /// Guilds, shards, wedges, the four-colour names, and five.
    static let nicknames: [String: String] = [
        "wu": "Azorius", "ub": "Dimir", "br": "Rakdos", "rg": "Gruul", "wg": "Selesnya",
        "wb": "Orzhov", "ur": "Izzet", "bg": "Golgari", "wr": "Boros", "ug": "Simic",
        "wub": "Esper", "ubr": "Grixis", "brg": "Jund", "wrg": "Naya", "wug": "Bant",
        "wbg": "Abzan", "wur": "Jeskai", "ubg": "Sultai", "wbr": "Mardu", "urg": "Temur",
        "wubr": "Yore-Tiller", "ubrg": "Glint-Eye", "wbrg": "Dune-Brood", "wurg": "Ink-Treader",
        "wubg": "Witch-Maw", "wubrg": "Five colour",
    ]
}

/// How a filter compares to its value, in the user's words and in Scryfall's.
public struct QueryOperator: Sendable, Hashable {
    /// What the button says: "fits within", "at least".
    public let word: String
    /// What goes in the query: `<=`, `>=`, `:`.
    public let symbol: String
    /// Rarity reads "Rare or better", so the word follows the value there.
    public let wordFollowsValue: Bool

    public init(_ word: String, _ symbol: String, wordFollowsValue: Bool = false) {
        self.word = word
        self.symbol = symbol
        self.wordFollowsValue = wordFollowsValue
    }

    static let numeric: [QueryOperator] = [
        QueryOperator("is", "="),
        QueryOperator("at most", "<="),
        QueryOperator("at least", ">="),
        QueryOperator("less than", "<"),
        QueryOperator("more than", ">"),
    ]
}

/// A ready-made value the builder offers as a button.
public struct QueryChoice: Sendable, Hashable, Identifiable {
    /// What the button says: "Creature", "First strike", "Colourless".
    public let label: String
    /// What goes after the operator: `creature`, `"first strike"`, `c`.
    public let syntax: String
    /// Some values only make sense with a colon (`mv:even`, `id:c`); this
    /// replaces whichever operator was picked.
    public let fixedSymbol: String?

    public var id: String { label }

    init(_ label: String, syntax: String? = nil, fixedSymbol: String? = nil) {
        self.label = label
        let text = syntax ?? label.lowercased()
        self.syntax = text.contains(" ") ? "\"\(text)\"" : text
        self.fixedSymbol = fixedSymbol
    }
}

/// What the builder can filter by, in the order it shows them.
public enum QueryFilter: String, Sendable, Hashable, CaseIterable, Identifiable {
    case identity = "id"
    case colour = "c"
    case type = "t"
    case manaValue = "mv"
    case rarity = "r"
    case format = "f"
    case power = "pow"
    case toughness = "tou"
    case keyword = "kw"
    case text = "o"

    public var id: String { rawValue }

    /// What kind of value the filter takes, which is what the screen draws.
    public enum Input: Sendable, Hashable {
        /// Five toggles, W U B R G, plus the choices.
        case colours
        /// Buttons, one per choice.
        case choices
        /// Words the user types; the builder hands off to the keyboard.
        case typed
    }

    public var title: String {
        switch self {
        case .identity: "Colour identity"
        case .colour: "Colour"
        case .type: "Type"
        case .manaValue: "Mana value"
        case .rarity: "Rarity"
        case .format: "Format"
        case .power: "Power"
        case .toughness: "Toughness"
        case .keyword: "Keyword"
        case .text: "Card text"
        }
    }

    public var input: Input {
        switch self {
        case .identity, .colour: .colours
        case .text: .typed
        default: .choices
        }
    }

    /// The first is the default.
    public var operators: [QueryOperator] {
        switch self {
        case .identity:
            [QueryOperator("fits within", "<="), QueryOperator("is exactly", "="), QueryOperator("includes", ">=")]
        case .colour:
            [QueryOperator("includes", ">="), QueryOperator("is exactly", "="), QueryOperator("fits within", "<=")]
        case .type: [QueryOperator("is", ":")]
        case .manaValue, .power, .toughness: QueryOperator.numeric
        case .rarity:
            [QueryOperator("is", ":"), QueryOperator("or better", ">=", wordFollowsValue: true),
             QueryOperator("or worse", "<=", wordFollowsValue: true)]
        case .format: [QueryOperator("legal in", ":")]
        case .keyword: [QueryOperator("has", ":")]
        case .text: [QueryOperator("contains", ":")]
        }
    }

    /// A filter with one operator has no operator step to show.
    public var hasOperatorStep: Bool { operators.count > 1 }

    /// Typed filters go straight from the filter to the keyboard.
    public var hasValueStep: Bool { input != .typed }

    public var choices: [QueryChoice] {
        switch self {
        case .identity:
            [QueryChoice("Colourless", syntax: "c", fixedSymbol: ":")]
        case .colour:
            [QueryChoice("Colourless", syntax: "c", fixedSymbol: ":"), QueryChoice("Multicolour", syntax: "m", fixedSymbol: ":")]
        case .type:
            ["Creature", "Instant", "Sorcery", "Artifact", "Enchantment", "Planeswalker", "Land", "Battle", "Legendary", "Token"]
                .map { QueryChoice($0) }
        case .manaValue:
            Self.digits + [QueryChoice("Even", fixedSymbol: ":"), QueryChoice("Odd", fixedSymbol: ":")]
        case .power, .toughness:
            Self.digits
        case .rarity:
            ["Common", "Uncommon", "Rare", "Mythic"].map { QueryChoice($0) }
        case .format:
            ["Commander", "Standard", "Modern", "Pioneer", "Pauper", "Legacy", "Vintage", "Brawl", "Alchemy"]
                .map { QueryChoice($0) }
        case .keyword:
            ["Flying", "Trample", "Haste", "Deathtouch", "Lifelink", "Flash", "Hexproof", "Vigilance", "Menace",
             "Ward", "First strike", "Double strike", "Reach", "Indestructible", "Defender"]
                .map { QueryChoice($0) }
        case .text:
            []
        }
    }

    /// Whether the value step also offers "Other…", which hands the filter
    /// to the keyboard with its prefix in place: creature types, for one.
    public var offersTyped: Bool { self == .type }

    /// 0 to 9. Anything larger is typed; this is a helper for beginners.
    private static let digits = (0...9).map { QueryChoice(String($0)) }

    /// The sentence for a finished value, with the placeholder `…` while
    /// there is none.
    func sentence(operator op: QueryOperator, value: String) -> String {
        switch self {
        case .identity: "Colour identity \(op.word) \(value)"
        case .colour: "Colour \(op.word) \(value)"
        case .type: "Type is \(value)"
        case .manaValue: "Mana value \(op.word) \(value)"
        case .power: "Power \(op.word) \(value)"
        case .toughness: "Toughness \(op.word) \(value)"
        case .rarity: op.wordFollowsValue ? "Rarity is \(value) \(op.word)" : "Rarity is \(value)"
        case .format: "Legal in \(value)"
        case .keyword: "Has \(value)"
        case .text: "Card text contains \(value)"
        }
    }
}

/// The value the user has picked, if any.
public enum QueryValue: Sendable, Hashable {
    case colours(Set<ManaColour>)
    case choice(QueryChoice)
    /// "Other…" or a typed filter: the clause ends at the operator and the
    /// keyboard takes over.
    case typed
}

/// One filter clause as the builder assembles it, and what it turns into.
public struct QueryClause: Sendable, Hashable {
    public var filter: QueryFilter
    /// Defaults to the filter's first operator.
    public var comparison: QueryOperator
    public var value: QueryValue?
    /// Prefixes `-`: "green cards that are not creatures".
    public var negated: Bool

    public init(filter: QueryFilter, comparison: QueryOperator? = nil, value: QueryValue? = nil, negated: Bool = false) {
        self.filter = filter
        self.comparison = comparison ?? filter.operators[0]
        self.value = filter.input == .typed ? .typed : value
        self.negated = negated
    }

    /// Whether the value is in. Add works without one (since 2026-09-25):
    /// the clause then ends at the operator and the keyboard takes the value.
    public var isComplete: Bool {
        switch value {
        case nil: false
        case .colours(let set): !set.isEmpty
        case .choice, .typed: true
        }
    }

    /// The clause ends at the operator and the keyboard should open: "Other…",
    /// a typed filter, or a value the user chose to type instead of picking.
    public var handsOffToKeyboard: Bool { value == .typed || !isComplete }

    /// The operator actually written: a choice such as Colourless overrides
    /// whichever was picked.
    private var symbol: String {
        if case .choice(let choice) = value, let fixed = choice.fixedSymbol { return fixed }
        return comparison.symbol
    }

    /// What goes in the search bar: `-id<=ub`, `t:creature`, `o:""`.
    public var syntax: String {
        var text = (negated ? "-" : "") + filter.rawValue + symbol
        switch value {
        case nil: break
        case .colours(let set): text += set.letters
        case .choice(let choice): text += choice.syntax
        case .typed: if filter.input == .typed { text += "\"\"" }
        }
        return text
    }

    /// How far from the end the caret belongs after adding: inside the empty
    /// quotes of `o:""`, otherwise at the end.
    public var caretFromEnd: Int {
        value == .typed && filter.input == .typed ? 1 : 0
    }

    /// What the clause means, in words: "Not: Colour identity fits within
    /// Blue and Black (Dimir)". `…` stands in for a missing value.
    public var sentence: String {
        let described: String
        switch value {
        case nil, .typed: described = "…"
        case .colours(let set): described = set.isEmpty ? "…" : set.description
        case .choice(let choice): described = choice.label
        }
        let op: QueryOperator
        if case .choice(let choice) = value, choice.fixedSymbol != nil {
            op = QueryOperator("is", ":")
        } else {
            op = comparison
        }
        return (negated ? "Not: " : "") + filter.sentence(operator: op, value: described)
    }
}
