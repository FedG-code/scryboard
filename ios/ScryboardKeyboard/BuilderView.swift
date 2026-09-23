import UIKit
import ScryboardKit

/// The query builder the keyboard opens on: filter, operator, value, one step
/// at a time, with a sentence saying what the clause means and the syntax it
/// becomes. Add hands the clause to the controller, which appends it to the
/// search bar without searching; Search runs whatever the bar holds.
///
/// Every decision about words and syntax is `QueryClause` in the Kit. This
/// view only draws buttons and keeps track of which step is showing.
final class BuilderView: UIView {
    var onAdd: ((QueryClause) -> Void)?
    var onSearch: (() -> Void)?

    /// Search is only offered while the bar has something to run.
    var canSearch = false {
        didSet { searchButton.isEnabled = canSearch }
    }

    private enum Step: Int, CaseIterable {
        case filter, comparison, value
    }

    private var clause: QueryClause?
    /// Not can be armed before a filter is picked; it then applies to the
    /// first clause built.
    private var negated = false
    private var step: Step = .filter

    private let sentenceLabel = UILabel()
    private let syntaxLabel = UILabel()
    private let crumbs = Step.allCases.map { _ in ChipButton(style: .function) }
    private let pane = FlowPane()
    private let notButton = ChipButton(style: .function)
    private let addButton = ChipButton(style: .plain)
    private let searchButton = ChipButton(style: .prominent)

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
        render()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Hierarchy

    private func build() {
        sentenceLabel.font = .systemFont(ofSize: 15)
        sentenceLabel.numberOfLines = 2
        sentenceLabel.adjustsFontSizeToFitWidth = true
        sentenceLabel.minimumScaleFactor = 0.8
        syntaxLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        syntaxLabel.textColor = .tintColor
        let sentence = UIStackView(arrangedSubviews: [sentenceLabel, syntaxLabel])
        sentence.axis = .vertical
        sentence.spacing = 2
        sentence.isLayoutMarginsRelativeArrangement = true
        sentence.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4)
        // The syntax line keeps its height when empty so nothing jumps.
        syntaxLabel.heightAnchor.constraint(equalToConstant: 15).isActive = true

        let crumbRow = UIStackView(arrangedSubviews: crumbs)
        crumbRow.spacing = 4
        crumbRow.distribution = .fillEqually
        crumbRow.heightAnchor.constraint(equalToConstant: 28).isActive = true
        for (index, crumb) in crumbs.enumerated() {
            crumb.font = .systemFont(ofSize: 12, weight: .medium)
            crumb.addAction(UIAction { [weak self] _ in self?.show(Step(rawValue: index)!) }, for: .touchUpInside)
        }

        notButton.title = "Not"
        notButton.accessibilityLabel = "Not: exclude these cards"
        notButton.addAction(UIAction { [weak self] _ in self?.toggleNegated() }, for: .touchUpInside)
        addButton.title = "Add"
        addButton.addAction(UIAction { [weak self] _ in self?.add() }, for: .touchUpInside)
        searchButton.title = "Search"
        searchButton.isEnabled = false
        searchButton.addAction(UIAction { [weak self] _ in self?.onSearch?() }, for: .touchUpInside)
        for button in [notButton, addButton, searchButton] {
            button.font = .systemFont(ofSize: 15, weight: .semibold)
        }
        let actions = UIStackView(arrangedSubviews: [notButton, addButton, searchButton])
        actions.spacing = 6
        actions.heightAnchor.constraint(equalToConstant: 40).isActive = true
        notButton.widthAnchor.constraint(equalToConstant: 64).isActive = true
        addButton.widthAnchor.constraint(equalTo: searchButton.widthAnchor, multiplier: 1.4).isActive = true

        let column = UIStackView(arrangedSubviews: [sentence, crumbRow, pane, actions])
        column.axis = .vertical
        column.spacing = 6
        column.isLayoutMarginsRelativeArrangement = true
        column.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 6, trailing: 8)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - State changes

    private func pick(_ filter: QueryFilter) {
        clause = QueryClause(filter: filter, negated: negated)
        step = filter.hasOperatorStep ? .comparison : (filter.hasValueStep ? .value : .filter)
        render()
    }

    private func pick(_ op: QueryOperator) {
        guard var clause else { return }
        clause.comparison = op
        // A choice that carries its own colon was picked under the old operator.
        if case .choice(let choice) = clause.value, choice.fixedSymbol != nil { clause.value = nil }
        self.clause = clause
        step = .value
        render()
    }

    private func toggle(_ colour: ManaColour) {
        guard var clause else { return }
        var set: Set<ManaColour> = []
        if case .colours(let current) = clause.value { set = current }
        if set.contains(colour) { set.remove(colour) } else { set.insert(colour) }
        clause.value = .colours(set)
        self.clause = clause
        render()
    }

    private func toggle(_ value: QueryValue) {
        guard var clause else { return }
        clause.value = clause.value == value ? nil : value
        self.clause = clause
        render()
    }

    private func toggleNegated() {
        negated.toggle()
        clause?.negated = negated
        render()
    }

    private func show(_ step: Step) {
        guard step == .filter || clause != nil else { return }
        self.step = step
        render()
    }

    private func add() {
        guard let clause, clause.isComplete else { return }
        onAdd?(clause)
        self.clause = nil
        negated = false
        step = .filter
        render()
    }

    // MARK: - Rendering

    private func render() {
        if let clause {
            sentenceLabel.text = clause.sentence
            sentenceLabel.textColor = .label
            syntaxLabel.text = clause.syntax + (clause.handsOffToKeyboard && clause.filter.input != .typed ? "…" : "")
        } else {
            sentenceLabel.text = "Pick what to filter by"
            sentenceLabel.textColor = .secondaryLabel
            syntaxLabel.text = nil
        }
        addButton.isEnabled = clause?.isComplete ?? false
        addButton.title = clause?.handsOffToKeyboard == true ? "Add and type" : "Add"
        notButton.isSelected = negated

        renderCrumbs()
        renderPane()
    }

    private func renderCrumbs() {
        let filter = clause?.filter
        let titles = ["Filter", "Operator", "Value"]
        let done: [String?] = [
            filter?.title,
            clause.map(\.comparison.word),
            clause.flatMap { clause -> String? in
                switch clause.value {
                case .colours(let set) where !set.isEmpty: set.description
                case .choice(let choice): choice.label
                default: nil
                }
            },
        ]
        let shown = [true, filter?.hasOperatorStep ?? true, filter?.hasValueStep ?? true]
        for (index, crumb) in crumbs.enumerated() {
            let current = index == step.rawValue
            crumb.isHidden = !shown[index]
            crumb.title = (current ? nil : done[index]) ?? titles[index]
            crumb.isSelected = current
            crumb.accessibilityLabel = "\(titles[index]) step" + (done[index].map { ", \($0)" } ?? "")
        }
    }

    private func renderPane() {
        var items: [FlowPane.Item] = []
        switch step {
        case .filter:
            if clause?.filter == .text {
                items.append(.full(hint("Card text is typed. Add puts o:\"\" in the search bar and opens the keyboard with the caret between the quotes.")))
            }
            for filter in QueryFilter.allCases {
                let chip = ChipButton(style: .plain)
                chip.title = filter.title
                chip.isSelected = clause?.filter == filter
                chip.addAction(UIAction { [weak self] _ in self?.pick(filter) }, for: .touchUpInside)
                items.append(.columns(chip, 3))
            }
        case .comparison:
            guard let clause else { break }
            for op in clause.filter.operators {
                let chip = ChipButton(style: .plain)
                chip.title = op.word
                chip.isSelected = clause.comparison == op
                chip.addAction(UIAction { [weak self] _ in self?.pick(op) }, for: .touchUpInside)
                items.append(.columns(chip, 2))
            }
        case .value:
            guard let clause else { break }
            let filter = clause.filter
            if filter.input == .colours {
                var picked: Set<ManaColour> = []
                if case .colours(let set) = clause.value { picked = set }
                for colour in ManaColour.allCases {
                    let chip = ChipButton(style: .plain)
                    chip.title = String(colour.rawValue).uppercased()
                    chip.font = .systemFont(ofSize: 18, weight: .bold)
                    chip.accessibilityLabel = colour.name
                    chip.isSelected = picked.contains(colour)
                    chip.addAction(UIAction { [weak self] _ in self?.toggle(colour) }, for: .touchUpInside)
                    items.append(.square(chip))
                }
            }
            let isNumeric = filter.choices.first?.label == "0"
            for choice in filter.choices {
                let chip = ChipButton(style: .plain)
                chip.title = choice.label
                chip.isSelected = clause.value == .choice(choice)
                chip.addAction(UIAction { [weak self] _ in self?.toggle(.choice(choice)) }, for: .touchUpInside)
                let digit = isNumeric && choice.label.count == 1 && choice.label.first!.isNumber
                items.append(.columns(chip, digit ? 5 : 2))
            }
            if filter.offersTyped {
                let chip = ChipButton(style: .plain)
                chip.title = "Other…"
                chip.accessibilityLabel = "Other: type it on the keyboard"
                chip.isSelected = clause.value == .typed
                chip.addAction(UIAction { [weak self] _ in self?.toggle(.typed) }, for: .touchUpInside)
                items.append(.columns(chip, 2))
            }
        }
        pane.items = items
    }

    private func hint(_ text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }
}

// MARK: - Chips

/// A key-shaped button with a centred title, laid out by hand like the
/// QWERTY's keys and for the same reason: a configuration `UIButton` created
/// while its stack is hidden keeps a zero-size layout until pressed.
final class ChipButton: UIControl {
    enum Style {
        /// Like a letter key. Selected inverts to label-on-background.
        case plain
        /// Like a function key: darker.
        case function
        /// The one action that leaves the screen: Search.
        case prominent
    }

    /// Also the accessibility label; set that afterwards to say more.
    var title: String? {
        didSet { label.text = title; accessibilityLabel = title }
    }

    var font: UIFont {
        get { label.font }
        set { label.font = newValue }
    }

    private let style: Style
    private let label = UILabel()

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        label.font = .systemFont(ofSize: 14)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75
        label.isUserInteractionEnabled = false
        addSubview(label)
        isAccessibilityElement = true
        accessibilityTraits = .button
        applyColours()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// The width the title wants, for the flow layout's arithmetic.
    var preferredWidth: CGFloat {
        label.intrinsicContentSize.width + 22
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 6, dy: 0)
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
    }

    override var isSelected: Bool {
        didSet {
            applyColours()
            if isSelected { accessibilityTraits.insert(.selected) } else { accessibilityTraits.remove(.selected) }
        }
    }

    override var isHighlighted: Bool {
        didSet { applyColours() }
    }

    override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1 : 0.45 }
    }

    private func applyColours() {
        let inverted = isSelected != isHighlighted
        switch style {
        case .plain:
            backgroundColor = inverted ? .label : .systemBackground
            label.textColor = inverted ? .systemBackground : .label
        case .function:
            backgroundColor = inverted ? .label : .systemFill
            label.textColor = inverted ? .systemBackground : .label
        case .prominent:
            backgroundColor = isHighlighted ? UIColor.tintColor.withAlphaComponent(0.7) : .tintColor
            label.textColor = .white
        }
    }
}

// MARK: - Flow layout

/// A scrolling pane that lays its items out left to right, wrapping into rows,
/// with each item as wide as a column of the pane. Hand-rolled because the
/// item widths are a handful of fixed rules, not content measurement.
final class FlowPane: UIScrollView {
    enum Item {
        /// One of `n` equal columns across the pane.
        case columns(UIView, Int)
        /// A 44-point square, for the mana letters.
        case square(UIView)
        /// The whole width, sized to its content: the hint text.
        case full(UIView)

        var view: UIView {
            switch self {
            case .columns(let view, _), .square(let view), .full(let view): view
            }
        }
    }

    var items: [Item] = [] {
        didSet {
            oldValue.forEach { $0.view.removeFromSuperview() }
            items.forEach { addSubview($0.view) }
            setContentOffset(.zero, animated: false)
            setNeedsLayout()
        }
    }

    private let gap: CGFloat = 6
    private let rowHeight: CGFloat = 36
    private let squareSide: CGFloat = 44

    override init(frame: CGRect) {
        super.init(frame: frame)
        showsVerticalScrollIndicator = false
        alwaysBounceVertical = false
        // A scroll must not swallow the tap that lands on a chip.
        delaysContentTouches = false
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func touchesShouldCancel(in view: UIView) -> Bool { true }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        guard width > 0 else { return }
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowTallest: CGFloat = 0

        for item in items {
            let size: CGSize
            switch item {
            case .columns(_, let count):
                size = CGSize(width: floor((width - gap * CGFloat(count - 1)) / CGFloat(count)), height: rowHeight)
            case .square:
                size = CGSize(width: squareSide, height: squareSide)
            case .full(let view):
                let fitted = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
                size = CGSize(width: width, height: fitted.height + 8)
            }
            if x > 0, x + size.width > width + 0.5 {
                x = 0
                y += rowTallest + gap
                rowTallest = 0
            }
            item.view.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
            x += size.width + gap
            rowTallest = max(rowTallest, size.height)
        }
        contentSize = CGSize(width: width, height: y + rowTallest)
    }
}
