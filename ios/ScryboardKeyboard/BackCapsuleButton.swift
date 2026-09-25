import UIKit

/// The floating "Back" capsule. One look for every way back in the keyboard:
/// it sits bottom-right over the grid while printings fill it, and
/// bottom-right over the builder's pane while a step can be undone.
final class BackCapsuleButton: UIButton {
    init() {
        super.init(frame: .zero)
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.image = UIImage(systemName: "chevron.left")
        config.imagePadding = 4
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        config.attributedTitle = AttributedString("Back", attributes: AttributeContainer([
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
        ]))
        config.baseBackgroundColor = .systemFill
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 14)
        configuration = config
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 5
        isHidden = true
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}
