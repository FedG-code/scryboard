import UIKit

/// The search-bar pill. Drawn by hand rather than a `UITextField`: a text field
/// inside a keyboard extension tries to summon a system keyboard that cannot
/// appear. Tapping it switches the keyboard into typing mode; the extension's
/// own QWERTY edits `query`.
final class SearchBarView: UIView {
    var onTap: (() -> Void)?
    var onClear: (() -> Void)?

    var query: String = "" {
        didSet { refresh() }
    }

    /// Shows the caret and hides the placeholder styling while the QWERTY is up.
    var isEditing = false {
        didSet { refresh() }
    }

    private let pill = UIView()
    private let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
    private let label = UILabel()
    private let caret = UIView()
    private let clearButton = UIButton(type: .system)

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
        label.lineBreakMode = .byTruncatingHead

        caret.backgroundColor = .tintColor
        caret.layer.cornerRadius = 1
        caret.widthAnchor.constraint(equalToConstant: 2).isActive = true
        caret.heightAnchor.constraint(equalToConstant: 22).isActive = true

        clearButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        clearButton.tintColor = .tertiaryLabel
        clearButton.accessibilityLabel = "Clear search"
        clearButton.setContentHuggingPriority(.required, for: .horizontal)
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [icon, label, caret, spacer, clearButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 6
        // The caret hugs the last letter; the stack's spacing would leave a
        // visible gap before it.
        row.setCustomSpacing(1, after: label)
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
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        pill.addGestureRecognizer(tap)
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
        caret.isHidden = !isEditing
        clearButton.isHidden = empty
        pill.accessibilityLabel = empty ? "Search cards" : query
        pill.accessibilityValue = isEditing ? "editing" : nil
        blink()
    }

    private func blink() {
        caret.layer.removeAllAnimations()
        guard isEditing else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0
        animation.duration = 0.5
        animation.autoreverses = true
        animation.repeatCount = .infinity
        caret.layer.add(animation, forKey: "blink")
    }

    @objc private func tapped() { onTap?() }
    @objc private func clearTapped() { onClear?() }
}
