import UIKit

/// A brief confirmation over the grid. Tenor does the same after a copy.
final class ToastView: UIView {
    private let label = UILabel()
    private var hideWork: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.label.withAlphaComponent(0.85)
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        alpha = 0
        isUserInteractionEnabled = false
        label.textColor = .systemBackground
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ text: String, for duration: TimeInterval = 1.6) {
        label.text = text
        hideWork?.cancel()
        UIView.animate(withDuration: 0.15) { self.alpha = 1 }
        let work = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.3) { self?.alpha = 0 }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
