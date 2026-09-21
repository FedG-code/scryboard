import UIKit

/// Card-name suggestions above the keys, from `/cards/autocomplete`. Tapping one
/// commits an exact-name search so the grid shows every printing of that card.
final class SuggestionStripView: UIView {
    var onSelect: ((String) -> Void)?

    private let scroll = UIScrollView()
    private let row = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        row.axis = .horizontal
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(row)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightAnchor.constraint(equalToConstant: 38),
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 4),
            row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -4),
            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -8),
            row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ names: [String]) {
        row.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for name in names {
            var configuration = UIButton.Configuration.filled()
            configuration.baseBackgroundColor = .secondarySystemFill
            configuration.baseForegroundColor = .label
            configuration.cornerStyle = .medium
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
            configuration.attributedTitle = AttributedString(name, attributes: AttributeContainer([
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
            ]))
            let button = UIButton(configuration: configuration)
            button.addAction(UIAction { [weak self] _ in self?.onSelect?(name) }, for: .touchUpInside)
            row.addArrangedSubview(button)
        }
        scroll.setContentOffset(.zero, animated: false)
    }
}
