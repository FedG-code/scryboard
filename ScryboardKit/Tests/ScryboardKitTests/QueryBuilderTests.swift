import Testing
@testable import ScryboardKit

@Suite("Query builder")
struct QueryBuilderTests {
    /// The reason the operators are words: Scryfall's colon means `>=` for
    /// colour and `<=` for identity. The builder writes what it says.
    @Test("Colour identity defaults to fits-within and never a bare colon")
    func identityDefaultsToFitsWithin() {
        let clause = QueryClause(filter: .identity, value: .colours([.blue, .black]))
        #expect(clause.syntax == "id<=ub")
        #expect(clause.sentence == "Colour identity fits within Blue and Black (Dimir)")
        #expect(clause.isComplete)
        #expect(!clause.handsOffToKeyboard)
    }

    @Test("Colour defaults to includes")
    func colourDefaultsToIncludes() {
        let clause = QueryClause(filter: .colour, value: .colours([.red, .green]))
        #expect(clause.syntax == "c>=rg")
        #expect(clause.sentence == "Colour includes Red and Green (Gruul)")
    }

    @Test("Letters come out in WUBRG order whatever the tap order")
    func wubrgOrder() {
        let set: Set<ManaColour> = [.green, .white, .black]
        #expect(set.letters == "wbg")
        #expect(set.description == "White, Black and Green (Abzan)")
        #expect(Set<ManaColour>([.white, .blue, .black, .red, .green]).description == "White, Blue, Black, Red and Green (Five colour)")
        #expect(Set<ManaColour>([.red]).description == "Red")
    }

    @Test("Colourless and multicolour force the colon whatever operator was picked")
    func fixedSymbolChoices() {
        let colourless = QueryFilter.identity.choices[0]
        let clause = QueryClause(filter: .identity, comparison: QueryOperator("is exactly", "="), value: .choice(colourless))
        #expect(clause.syntax == "id:c")
        #expect(clause.sentence == "Colour identity is Colourless")

        let even = QueryFilter.manaValue.choices.first { $0.label == "Even" }!
        #expect(QueryClause(filter: .manaValue, comparison: QueryOperator("at most", "<="), value: .choice(even)).syntax == "mv:even")
    }

    @Test("Not prefixes a minus")
    func negation() {
        let creature = QueryFilter.type.choices[0]
        let clause = QueryClause(filter: .type, value: .choice(creature), negated: true)
        #expect(clause.syntax == "-t:creature")
        #expect(clause.sentence == "Not: Type is Creature")
    }

    @Test("Values with spaces are quoted")
    func quotedValues() {
        let firstStrike = QueryFilter.keyword.choices.first { $0.label == "First strike" }!
        let clause = QueryClause(filter: .keyword, value: .choice(firstStrike))
        #expect(clause.syntax == "kw:\"first strike\"")
        #expect(clause.sentence == "Has First strike")
    }

    @Test("Rarity reads value first for or-better")
    func rarityWording() {
        let rare = QueryFilter.rarity.choices.first { $0.label == "Rare" }!
        let better = QueryFilter.rarity.operators[1]
        let clause = QueryClause(filter: .rarity, comparison: better, value: .choice(rare))
        #expect(clause.syntax == "r>=rare")
        #expect(clause.sentence == "Rarity is Rare or better")
        #expect(QueryClause(filter: .rarity, value: .choice(rare)).sentence == "Rarity is Rare")
    }

    @Test("Numbers compare with the operator's symbol")
    func numeric() {
        let three = QueryFilter.manaValue.choices[3]
        let atMost = QueryFilter.manaValue.operators[1]
        let clause = QueryClause(filter: .manaValue, comparison: atMost, value: .choice(three))
        #expect(clause.syntax == "mv<=3")
        #expect(clause.sentence == "Mana value at most 3")
        #expect(QueryClause(filter: .power, comparison: QueryFilter.power.operators[2], value: .choice(QueryFilter.power.choices[5])).syntax == "pow>=5")
    }

    /// Card text needs words, so the clause is the empty quotes and the
    /// caret belongs between them for the keyboard to fill.
    @Test("Card text hands off to the keyboard with the caret inside the quotes")
    func cardTextHandsOff() {
        let clause = QueryClause(filter: .text)
        #expect(clause.isComplete, "picking the filter is enough; Add opens the keyboard")
        #expect(clause.handsOffToKeyboard)
        #expect(clause.syntax == "o:\"\"")
        #expect(clause.caretFromEnd == 1)
        #expect(clause.sentence == "Card text contains …")
        #expect(!QueryFilter.text.hasOperatorStep)
        #expect(!QueryFilter.text.hasValueStep)

        var buffer = QueryBuffer("t:creature")
        buffer.appendTerm(clause.syntax, caretFromEnd: clause.caretFromEnd)
        buffer.insert("draw a card")
        #expect(buffer.text == "t:creature o:\"draw a card\"")
    }

    @Test("Other… under Type leaves the prefix for the keyboard")
    func typeOther() {
        let clause = QueryClause(filter: .type, value: .typed)
        #expect(QueryFilter.type.offersTyped)
        #expect(clause.syntax == "t:")
        #expect(clause.caretFromEnd == 0)
        #expect(clause.handsOffToKeyboard)
    }

    @Test("A clause without a value is incomplete and says so")
    func incomplete() {
        #expect(!QueryClause(filter: .identity).isComplete)
        #expect(!QueryClause(filter: .identity, value: .colours([])).isComplete)
        #expect(QueryClause(filter: .identity).sentence == "Colour identity fits within …")
        #expect(QueryClause(filter: .rarity).sentence == "Rarity is …")
    }

    @Test("Only filters with several operators show the operator step")
    func operatorStep() {
        #expect(QueryFilter.identity.hasOperatorStep)
        #expect(QueryFilter.manaValue.hasOperatorStep)
        #expect(QueryFilter.rarity.hasOperatorStep)
        for filter in [QueryFilter.type, .format, .keyword, .text] {
            #expect(!filter.hasOperatorStep, "\(filter) has one operator")
        }
    }

    /// Every button in the catalogue must produce a clause Scryfall parses:
    /// no spaces outside quotes, the filter's own keyword, a known operator.
    @Test("Every choice of every filter produces one clean token")
    func everyChoiceIsOneToken() {
        for filter in QueryFilter.allCases {
            for op in filter.operators {
                for choice in filter.choices {
                    let clause = QueryClause(filter: filter, comparison: op, value: .choice(choice))
                    let syntax = clause.syntax
                    #expect(syntax.hasPrefix(filter.rawValue), "\(syntax)")
                    let unquoted = syntax.split(separator: "\"").enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element).joined()
                    #expect(!unquoted.contains(" "), "\(syntax) has a space outside quotes")
                    #expect(clause.isComplete)
                }
            }
        }
    }

    @Test("Every filter reaches the keyboard's characters")
    func syntaxIsTypeable() {
        let reachable = KeyboardLayout.charactersReachable
        for filter in QueryFilter.allCases {
            for op in filter.operators {
                for character in filter.rawValue + op.symbol {
                    #expect(reachable.contains(character), "cannot type \(character) from \(filter)")
                }
            }
        }
    }
}
