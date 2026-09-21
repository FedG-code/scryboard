import UIKit

/// A globe under the grid, for systems that expect the keyboard to provide
/// one (`needsInputModeSwitchKey`). iOS 26 draws its own and this strip is
/// hidden, so the grid gets the room. No delete key: in browsing mode there is
/// nothing to delete from, and the host app's text is not the keyboard's job.
final class BrowseToolbarView: UIView {
    let globeButton = UIButton(configuration: .gray())

    override init(frame: CGRect) {
        super.init(frame: frame)

        globeButton.configuration?.image = UIImage(systemName: "globe")
        globeButton.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20)
        globeButton.configuration?.baseForegroundColor = .label
        globeButton.accessibilityLabel = "Next keyboard"
        globeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(globeButton)

        NSLayoutConstraint.activate([
            globeButton.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            globeButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            globeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}
