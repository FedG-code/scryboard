import UIKit

/// The strip under the grid: the two keys Apple requires, available even when
/// the QWERTY is hidden. Delete here acts on the host app's text, exactly as
/// the emoji keyboard's delete does.
final class BrowseToolbarView: UIView {
    let globeButton = UIButton(configuration: .gray())
    let deleteButton = UIButton(configuration: .gray())

    override init(frame: CGRect) {
        super.init(frame: frame)

        globeButton.configuration?.image = UIImage(systemName: "globe")
        globeButton.accessibilityLabel = "Next keyboard"
        deleteButton.configuration?.image = UIImage(systemName: "delete.left")
        deleteButton.accessibilityLabel = "Delete"
        for button in [globeButton, deleteButton] {
            button.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20)
            button.configuration?.baseForegroundColor = .label
        }

        let row = UIStackView(arrangedSubviews: [globeButton, UIView(), deleteButton])
        row.axis = .horizontal
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}
