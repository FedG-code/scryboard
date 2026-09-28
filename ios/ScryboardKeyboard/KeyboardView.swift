import UIKit
import ScryboardKit

/// Renders a `KeyboardLayout` and reports taps. Every decision about what a
/// key *does* lives in `KeyboardState`; this view only draws and listens.
///
/// Layout is done by hand in `layoutSubviews` rather than with stack views:
/// key widths are relative units, rows have different totals, and centring
/// each row within the widest one is what makes the layout look like the
/// system keyboard on every device width.
///
/// The metrics are the system keyboard's as measured by replicas (see
/// `KeyStyle`): 42 pt keys on a 54 pt row pitch, 6 pt between keys, 3 pt at
/// the sides. Rows shrink together when the height on offer is less, as in
/// landscape.
final class KeyboardView: UIView, UIInputViewAudioFeedback {
    var onAction: ((KeyAction) -> Void)?
    var onShiftDoubleTap: (() -> Void)?

    /// Wired to the globe key so a long press shows the system keyboard
    /// picker, which is Apple's expected behaviour for the key.
    weak var inputModeListHandler: UIInputViewController?

    /// `false` when the system draws its own globe under the keyboard
    /// (`needsInputModeSwitchKey == false`); the space bar takes the room.
    var showsGlobeKey = true

    /// The system click on every key, through `UIDevice.playInputClick()`.
    var enableInputClicksWhenVisible: Bool { true }

    private var layout: KeyboardLayout?
    private var rowViews: [[KeyButton]] = []
    private var repeatTimer: Timer?
    private var lastShiftTap: TimeInterval = 0
    /// The enlarged character over a pressed letter key.
    private let popup = KeyPopupView()

    private let horizontalInset: CGFloat = 3
    private let topInset: CGFloat = 6
    private let bottomInset: CGFloat = 8
    private let keyGap: CGFloat = 6
    private let keyHeight: CGFloat = 42
    private let rowGap: CGFloat = 12
    /// In landscape the rows are too short for the full gap.
    private let cramped: CGFloat = 6

    override init(frame: CGRect) {
        super.init(frame: frame)
        popup.isHidden = true
        addSubview(popup)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

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
        popup.isHidden = true
        rowViews.flatMap { $0 }.forEach { $0.removeFromSuperview() }
        rowViews = layout.rows.map { row in
            row.keys.map { key in
                let button = KeyButton(key: key)
                addSubview(button)
                wire(button)
                return button
            }
        }
        bringSubviewToFront(popup)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let layout, !rowViews.isEmpty else { return }

        let availableWidth = bounds.width - horizontalInset * 2
        let availableHeight = bounds.height - topInset - bottomInset
        let maxUnits = layout.rows.map(\.widthUnits).max() ?? 1
        let unit = availableWidth / maxUnits
        let rowCount = CGFloat(layout.rows.count)
        // The system pitch when it fits; otherwise everything shrinks.
        let wanted = keyHeight * rowCount + rowGap * (rowCount - 1)
        let gap = wanted <= availableHeight ? rowGap : cramped
        let rowHeight = min(keyHeight, (availableHeight - gap * (rowCount - 1)) / rowCount)

        for (rowIndex, row) in layout.rows.enumerated() {
            let rowWidth = row.widthUnits * unit
            var x = horizontalInset + (availableWidth - rowWidth) / 2
            let y = topInset + CGFloat(rowIndex) * (rowHeight + gap)
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
        button.addTarget(self, action: #selector(keyDown(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(keyReleased(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
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

    /// The click, and for a character key the pop-up: the system keyboard's
    /// two signs that a key registered.
    @objc private func keyDown(_ button: KeyButton) {
        UIDevice.current.playInputClick()
        guard case .character = button.key.action else { return }
        popup.text = button.key.label
        popup.frame = KeyPopupView.frame(over: button.frame)
        popup.isHidden = false
    }

    @objc private func keyReleased(_ button: KeyButton) {
        popup.isHidden = true
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
/// keyboard, so the eye finds the edges of the alphabet without reading. The
/// search key is blue: the system's return key when it has an action.
///
/// A plain control with a centred label, laid out by hand. The first version
/// was a configuration-based `UIButton`; created while the typing stack was
/// hidden, it laid its title out at zero size and kept that layout until the
/// key was pressed, so every label sat at the top of its key on first open.
private final class KeyButton: UIControl {
    let key: KeyboardKey

    private let label = UILabel()
    private let symbol = UIImageView()
    private let restingColor: UIColor
    private let pressedColor: UIColor
    private let restingInk: UIColor
    private let pressedInk: UIColor

    init(key: KeyboardKey) {
        self.key = key
        // Pressing swaps the two greys, which is what the system keyboard
        // does; the blue key goes white with dark ink.
        switch key.role {
        case .letter:
            restingColor = KeyStyle.letterKey
            pressedColor = KeyStyle.functionKey
            restingInk = .label
            pressedInk = .label
        case .function:
            restingColor = KeyStyle.functionKey
            pressedColor = KeyStyle.letterKey
            restingInk = .label
            pressedInk = .label
        case .action:
            restingColor = KeyStyle.actionKey
            pressedColor = KeyStyle.letterKey
            restingInk = .white
            pressedInk = .label
        }
        super.init(frame: .zero)

        backgroundColor = restingColor
        layer.cornerRadius = KeyStyle.cornerRadius
        layer.cornerCurve = .continuous
        KeyStyle.applyShadow(to: layer, traits: traitCollection)

        if let name = key.symbolName {
            symbol.image = UIImage(systemName: name)
            symbol.preferredSymbolConfiguration = KeyStyle.symbolConfiguration
            symbol.tintColor = restingInk
            symbol.contentMode = .center
            symbol.isUserInteractionEnabled = false
            addSubview(symbol)
        } else {
            label.text = key.label
            label.font = key.role == .function ? KeyStyle.functionFont : KeyStyle.characterFont(for: key.label)
            label.textColor = restingInk
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.7
            label.isUserInteractionEnabled = false
            addSubview(label)
        }

        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
        accessibilityLabel = key.accessibilityLabel
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
        symbol.frame = bounds
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        KeyStyle.applyShadow(to: layer, traits: traitCollection)
    }

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted ? pressedColor : restingColor
            label.textColor = isHighlighted ? pressedInk : restingInk
            symbol.tintColor = isHighlighted ? pressedInk : restingInk
        }
    }
}

/// The bubble that rises over a pressed letter key with the character large
/// in it. Covers the key and reaches above it; the keyboard view does not
/// clip, so the top row's bubble rides over the search bar as the system's
/// rides over the host.
private final class KeyPopupView: UIView {
    var text: String? {
        didSet { label.text = text }
    }

    private let label = UILabel()
    private static let rise: CGFloat = 50
    private static let widen: CGFloat = 26

    init() {
        super.init(frame: .zero)
        backgroundColor = KeyStyle.letterKey
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.black.withAlphaComponent(0.5).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.1
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 5
        isUserInteractionEnabled = false
        label.font = .systemFont(ofSize: 34, weight: .light)
        label.textColor = .label
        label.textAlignment = .center
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Where the bubble goes for a key at `keyFrame`, in the same coordinates.
    static func frame(over keyFrame: CGRect) -> CGRect {
        CGRect(
            x: keyFrame.midX - (keyFrame.width + widen) / 2,
            y: keyFrame.minY - rise,
            width: keyFrame.width + widen,
            height: keyFrame.height + rise
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The character sits in the risen part, above the covered key.
        label.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Self.rise)
    }
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
    enum Role {
        /// Characters and the space bar: the light keys.
        case letter
        /// Shift, delete, planes, globe, the builder key: the dark keys.
        case function
        /// Search: the blue key.
        case action
    }

    var role: Role {
        switch action {
        case .character, .space: .letter
        case .search: .action
        default: .function
        }
    }

    /// Keys drawn with an SF Symbol rather than their layout label, for the
    /// system keyboard's look. Space is deliberately blank: people know.
    /// The builder key is the "filter" glyph iOS Mail teaches, chosen on
    /// 2026-09-28 over the sliders, which read as settings; the runners-up
    /// if it ever needs swapping are `rectangle.3.group` and
    /// `text.magnifyingglass`.
    var symbolName: String? {
        switch action {
        case .search: "return"
        case .backspace: "delete.left"
        case .nextInputMode: "globe"
        case .builder: "line.3.horizontal.decrease"
        case .shift: label == "⇪" ? "capslock.fill" : "shift"
        case .character, .space, .plane: nil
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
        case .builder: "Query builder"
        }
    }
}
