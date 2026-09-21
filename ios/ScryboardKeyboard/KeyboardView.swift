import UIKit
import ScryboardKit

/// Renders a `KeyboardLayout` and reports taps. Every decision about what a
/// key *does* lives in `KeyboardState`; this view only draws and listens.
///
/// Layout is done by hand in `layoutSubviews` rather than with stack views:
/// key widths are relative units, rows have different totals, and centring
/// each row within the widest one is what makes the layout look like the
/// system keyboard on every device width.
final class KeyboardView: UIView {
    var onAction: ((KeyAction) -> Void)?
    var onShiftDoubleTap: (() -> Void)?

    /// Wired to the globe key so a long press shows the system keyboard
    /// picker, which is Apple's expected behaviour for the key.
    weak var inputModeListHandler: UIInputViewController?

    /// `false` when the system draws its own globe under the keyboard
    /// (`needsInputModeSwitchKey == false`); the space bar takes the room.
    var showsGlobeKey = true

    private var layout: KeyboardLayout?
    private var rowViews: [[KeyButton]] = []
    private var repeatTimer: Timer?
    private var lastShiftTap: TimeInterval = 0

    private let horizontalInset: CGFloat = 3
    private let verticalInset: CGFloat = 8
    private let keyGap: CGFloat = 6
    private let rowGap: CGFloat = 10

    override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)
        // A repeating timer retains its closure, which retains nothing strong,
        // but the timer itself would keep firing into the void. Stop it when
        // the view leaves the hierarchy; deinit is nonisolated under Swift 6.
        if newSuperview == nil { repeatingKeyUp() }
    }

    // MARK: - Rendering

    func render(_ layout: KeyboardLayout) {
        let layout = showsGlobeKey ? layout : layout.withoutGlobeKey()
        guard layout != self.layout else { return }
        self.layout = layout
        rowViews.flatMap { $0 }.forEach { $0.removeFromSuperview() }
        rowViews = layout.rows.map { row in
            row.keys.map { key in
                let button = KeyButton(key: key)
                addSubview(button)
                wire(button)
                return button
            }
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let layout, !rowViews.isEmpty else { return }

        let availableWidth = bounds.width - horizontalInset * 2
        let availableHeight = bounds.height - verticalInset * 2
        let maxUnits = layout.rows.map(\.widthUnits).max() ?? 1
        let unit = availableWidth / maxUnits
        let rowCount = CGFloat(layout.rows.count)
        let rowHeight = (availableHeight - rowGap * (rowCount - 1)) / rowCount

        for (rowIndex, row) in layout.rows.enumerated() {
            let rowWidth = row.widthUnits * unit
            var x = horizontalInset + (availableWidth - rowWidth) / 2
            let y = verticalInset + CGFloat(rowIndex) * (rowHeight + rowGap)
            for (keyIndex, key) in row.keys.enumerated() {
                let width = key.widthUnits * unit
                rowViews[rowIndex][keyIndex].frame = CGRect(
                    x: x + keyGap / 2, y: y, width: width - keyGap, height: rowHeight
                )
                x += width
            }
        }
    }

    // MARK: - Touch handling

    private func wire(_ button: KeyButton) {
        switch button.key.action {
        case .nextInputMode:
            if let handler = inputModeListHandler {
                button.addTarget(handler, action: #selector(UIInputViewController.handleInputModeList(from:with:)), for: .allTouchEvents)
            } else {
                button.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
            }
        case .backspace:
            button.addTarget(self, action: #selector(repeatingKeyDown(_:)), for: .touchDown)
            button.addTarget(self, action: #selector(repeatingKeyUp), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        case .shift:
            button.addTarget(self, action: #selector(shiftTapped(_:)), for: .touchUpInside)
        default:
            button.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
        }
    }

    @objc private func keyTapped(_ button: KeyButton) {
        onAction?(button.key.action)
    }

    @objc private func shiftTapped(_ button: KeyButton) {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastShiftTap < 0.3 {
            lastShiftTap = 0
            onShiftDoubleTap?()
        } else {
            lastShiftTap = now
            onAction?(.shift)
        }
    }

    @objc private func repeatingKeyDown(_ button: KeyButton) {
        onAction?(button.key.action)
        repeatTimer?.invalidate()
        // Same feel as the system keyboard: a pause, then steady repeats.
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self, weak button] _ in
            MainActor.assumeIsolated {
                guard let self, let button else { return }
                self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self, weak button] _ in
                    MainActor.assumeIsolated {
                        guard let self, let button else { return }
                        self.onAction?(button.key.action)
                    }
                }
            }
        }
    }

    @objc private func repeatingKeyUp() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}

/// One keycap. Letter keys are light, function keys darker, as on the system
/// keyboard, so the eye finds the edges of the alphabet without reading.
private final class KeyButton: UIButton {
    let key: KeyboardKey

    init(key: KeyboardKey) {
        self.key = key
        super.init(frame: .zero)

        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .medium
        configuration.contentInsets = .zero
        configuration.baseForegroundColor = .label
        configuration.baseBackgroundColor = key.isFunctionKey ? .systemFill : .systemBackground
        let font: UIFont = key.isFunctionKey
            ? .systemFont(ofSize: 16, weight: .regular)
            : .systemFont(ofSize: 22, weight: .regular)
        configuration.attributedTitle = AttributedString(key.label, attributes: AttributeContainer([.font: font]))
        self.configuration = configuration

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        accessibilityLabel = key.accessibilityLabel
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}

private extension KeyboardLayout {
    /// Drops the globe key and hands its width to the space bar, so the row
    /// keeps its width and the remaining keys keep their positions.
    func withoutGlobeKey() -> KeyboardLayout {
        KeyboardLayout(rows: rows.map { row in
            let globeUnits = row.keys.filter { $0.action == .nextInputMode }.reduce(0) { $0 + $1.widthUnits }
            guard globeUnits > 0 else { return row }
            return KeyboardRow(row.keys.compactMap { key in
                switch key.action {
                case .nextInputMode:
                    return nil
                case .space:
                    return KeyboardKey(id: key.id, action: key.action, label: key.label,
                                       widthUnits: key.widthUnits + globeUnits, repeatsOnHold: key.repeatsOnHold)
                default:
                    return key
                }
            })
        })
    }
}

private extension KeyboardKey {
    var isFunctionKey: Bool {
        switch action {
        case .character, .space: false
        default: true
        }
    }

    var accessibilityLabel: String {
        switch action {
        case .character(let text): text
        case .space: "Space"
        case .backspace: "Delete"
        case .shift: "Shift"
        case .plane(let plane): "Switch to \(plane.rawValue)"
        case .nextInputMode: "Next keyboard"
        case .search: "Search"
        }
    }
}
