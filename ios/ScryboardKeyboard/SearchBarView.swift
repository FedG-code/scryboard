import UIKit

/// The search-bar pill. Drawn by hand rather than a `UITextField`: a text field
/// inside a keyboard extension tries to summon a system keyboard that cannot
/// appear. Tapping it switches the keyboard into typing mode; the extension's
/// own QWERTY edits `query`.
///
/// The caret is real: it sits at `caret` characters into the text, a tap on
/// the text moves it to the nearest gap between letters and a drag slides it,
/// so a typo early in a query can be fixed without retyping the rest.
final class SearchBarView: UIView {
    var onTap: (() -> Void)?
    var onClear: (() -> Void)?
    /// The user put the caret somewhere. The offset counts characters.
    var onMoveCaret: ((Int) -> Void)?

    var query: String = "" {
        didSet { refresh() }
    }

    /// Where the caret is drawn, `0...query.count`.
    var caret: Int = 0 {
        didSet { textArea.setNeedsLayout() }
    }

    /// Shows the caret and hides the placeholder styling while the QWERTY is up.
    var isEditing = false {
        didSet { refresh() }
    }

    private let pill = UIView()
    private let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
    /// Clips a query longer than the pill and scrolls to keep the caret in view.
    private let textArea = TextArea()
    private let label = UILabel()
    private let caretView = UIView()
    private let clearButton = UIButton(type: .system)
    /// The x position of every gap between characters, measured at layout.
    private var gaps: [CGFloat] = [0]

    private static let caretWidth: CGFloat = 2

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func build() {
        pill.backgroundColor = .tertiarySystemFill
        pill.layer.cornerRadius = 10
        pill.layer.cornerCurve = .continuous
        pill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pill)

        icon.tintColor = .secondaryLabel
        icon.setContentHuggingPriority(.required, for: .horizontal)

        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true

        caretView.backgroundColor = .tintColor
        caretView.layer.cornerRadius = 1

        // Scrolling is ours to do: a drag across the text moves the caret.
        textArea.isScrollEnabled = false
        textArea.showsHorizontalScrollIndicator = false
        textArea.clipsToBounds = true
        textArea.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textArea.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textArea.addSubview(label)
        textArea.addSubview(caretView)
        textArea.onLayout = { [weak self] in self?.layoutText() }

        clearButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        clearButton.tintColor = .tertiaryLabel
        clearButton.accessibilityLabel = "Clear search"
        clearButton.setContentHuggingPriority(.required, for: .horizontal)
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [icon, textArea, clearButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(row)

        NSLayoutConstraint.activate([
            pill.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            pill.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            pill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            pill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            pill.heightAnchor.constraint(equalToConstant: 36),
            row.topAnchor.constraint(equalTo: pill.topAnchor),
            row.bottomAnchor.constraint(equalTo: pill.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -6),
            textArea.heightAnchor.constraint(equalTo: row.heightAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        pill.addGestureRecognizer(tap)
        let drag = UIPanGestureRecognizer(target: self, action: #selector(dragged(_:)))
        pill.addGestureRecognizer(drag)
        isAccessibilityElement = false
        pill.isAccessibilityElement = true
        pill.accessibilityTraits = .searchField
    }

    private func refresh() {
        let empty = query.isEmpty
        // The placeholder shows only while the bar is idle. Once the user is
        // typing, an empty bar is an empty bar with the caret at its start.
        label.text = empty && !isEditing ? "Search cards" : query
        label.textColor = empty ? .placeholderText : .label
        caretView.isHidden = !isEditing
        clearButton.isHidden = empty
        pill.accessibilityLabel = empty ? "Search cards" : query
        pill.accessibilityValue = isEditing ? "editing" : nil
        textArea.setNeedsLayout()
        blink()
    }

    // MARK: - Layout

    /// Frames inside the scroll area. Runs from the area's own layout pass,
    /// once it has its size: the pill's pass comes first, when the area is
    /// still zero-height, and placing the text then left it floating above
    /// the pill. Frames snap to whole points so the glyphs stay sharp.
    private func layoutText() {
        measureGaps()

        let area = textArea.bounds
        let textWidth = gaps[gaps.count - 1].rounded(.up)
        let labelHeight = label.font.lineHeight.rounded(.up)
        label.frame = CGRect(x: 0, y: ((area.height - labelHeight) / 2).rounded(), width: textWidth, height: labelHeight)

        let caretHeight: CGFloat = 22
        let caretX = gaps[min(max(caret, 0), gaps.count - 1)].rounded()
        caretView.frame = CGRect(x: caretX, y: ((area.height - caretHeight) / 2).rounded(), width: Self.caretWidth, height: caretHeight)

        textArea.contentSize = CGSize(width: max(textWidth + Self.caretWidth, area.width), height: area.height)
        // Keep the caret on screen: a long query slides left under it, and
        // the caret at the end shows the tail, as the old head truncation did.
        var offset = textArea.contentOffset.x
        let farthest = max(textArea.contentSize.width - area.width, 0)
        if isEditing {
            if caretX + Self.caretWidth > offset + area.width {
                offset = caretX + Self.caretWidth - area.width
            } else if caretX < offset {
                offset = caretX
            }
        } else {
            offset = farthest
        }
        textArea.contentOffset.x = min(max(offset, 0), farthest).rounded()
    }

    /// The x of each gap between characters of the drawn text, from the start
    /// of the label. Measured by prefix so kerning inside the run is honoured.
    private func measureGaps() {
        let text = label.text ?? ""
        let attributes: [NSAttributedString.Key: Any] = [.font: label.font as Any]
        var measured: [CGFloat] = [0]
        measured.reserveCapacity(text.count + 1)
        var end = text.startIndex
        while end < text.endIndex {
            end = text.index(after: end)
            measured.append((String(text[..<end]) as NSString).size(withAttributes: attributes).width)
        }
        gaps = measured
    }

    /// The gap nearest a point in the pill. Beyond either end clamps.
    private func gap(nearest point: CGPoint) -> Int {
        let x = pill.convert(point, to: textArea).x
        var best = 0
        var distance = CGFloat.infinity
        for (index, gapX) in gaps.enumerated() where abs(gapX - x) < distance {
            best = index
            distance = abs(gapX - x)
        }
        return best
    }

    private func blink() {
        caretView.layer.removeAllAnimations()
        guard isEditing else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0
        animation.duration = 0.5
        animation.autoreverses = true
        animation.repeatCount = .infinity
        caretView.layer.add(animation, forKey: "blink")
    }

    // MARK: - Gestures

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard isEditing else {
            onTap?()
            return
        }
        onMoveCaret?(gap(nearest: gesture.location(in: pill)))
        blink()
    }

    @objc private func dragged(_ gesture: UIPanGestureRecognizer) {
        guard isEditing else { return }
        switch gesture.state {
        case .began, .changed:
            let target = gap(nearest: gesture.location(in: pill))
            if target != caret { onMoveCaret?(target) }
            // Hold the caret solid while it is being moved.
            caretView.layer.removeAllAnimations()
        default:
            blink()
        }
    }

    @objc private func clearTapped() { onClear?() }
}

/// A scroll view that hands its layout pass to its owner.
private final class TextArea: UIScrollView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
