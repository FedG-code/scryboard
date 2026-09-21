import UIKit
import ScryboardKit

/// Milestone 2 skeleton: proves the extension loads, links ScryboardKit, and
/// offers the two keys Apple requires. Milestone 3 replaces the body with the
/// grid/typing mode switch.
final class KeyboardViewController: UIInputViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let title = UILabel()
        title.text = "Scryboard"
        title.font = .preferredFont(forTextStyle: .headline)
        title.textAlignment = .center

        let toolbar = UIStackView(arrangedSubviews: [makeGlobeKey(), UIView(), makeDeleteKey()])
        toolbar.axis = .horizontal
        toolbar.spacing = 8

        let column = UIStackView(arrangedSubviews: [title, toolbar])
        column.axis = .vertical
        column.spacing = 12
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)

        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            column.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12),
        ])
    }

    // MARK: - Required keys

    /// The globe key. `handleInputModeList(from:with:)` on all touch events is
    /// Apple's pattern: a tap switches keyboards, a long press shows the picker.
    private func makeGlobeKey() -> UIButton {
        let button = makeKey(title: "🌐", accessibilityLabel: "Next keyboard")
        button.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        return button
    }

    /// In grid mode delete acts on the host app's text, like the emoji keyboard.
    private func makeDeleteKey() -> UIButton {
        let button = makeKey(title: "⌫", accessibilityLabel: "Delete")
        button.addTarget(self, action: #selector(deleteBackward), for: .touchUpInside)
        return button
    }

    @objc private func deleteBackward() {
        textDocumentProxy.deleteBackward()
    }

    private func makeKey(title: String, accessibilityLabel: String) -> UIButton {
        var configuration = UIButton.Configuration.gray()
        configuration.title = title
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = accessibilityLabel
        return button
    }
}
