import UIKit

/// The system keyboard's key colours and metrics, so every key-shaped thing
/// in the extension (keys, builder chips) draws the same way. Apple publishes
/// none of this; the values are the ones open-source replicas measured
/// against the system keyboard (KeyboardKit, Tasty Imitation Keyboard,
/// Pereira), settled on 2026-09-28 from the "system replica" mock-up in
/// `docs/prototypes/native-keys-ios.html`.
///
/// Fixed colours rather than `systemBackground` / `systemFill`: the system's
/// dark keys are a mid grey (white at about 30 % over the backdrop), not
/// black, and its function keys are a blue-grey no semantic colour gives.
enum KeyStyle {
    /// Letter keys, the space bar, the builder's plain chips.
    static let letterKey = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0x6B / 255, alpha: 1) : .white
    }

    /// Shift, delete, `123`, globe, the builder key, Not: the darker keys.
    static let functionKey = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0x47 / 255, alpha: 1)
            : UIColor(red: 0xAB / 255, green: 0xB1 / 255, blue: 0xBA / 255, alpha: 1)
    }

    /// The return key when it has an action: system blue with white on it.
    static let actionKey = UIColor.systemBlue

    /// Key corners. Chips share it so the builder reads as part of the keyboard.
    static let cornerRadius: CGFloat = 5

    /// A key is a card lying on the backdrop: one hard point of shadow under
    /// its bottom edge, no blur. Darker in dark mode, where the backdrop is.
    static func applyShadow(to layer: CALayer, traits: UITraitCollection) {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = traits.userInterfaceStyle == .dark ? 0.7 : 0.3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
    }

    /// Lowercase letters are large and light; uppercase and symbols a little
    /// smaller and regular, as on the system keyboard.
    static func characterFont(for label: String) -> UIFont {
        let lowercase = label.count == 1 && label.first!.isLetter && label.first!.isLowercase
        return lowercase ? .systemFont(ofSize: 25, weight: .light) : .systemFont(ofSize: 22, weight: .regular)
    }

    /// `123`, `ABC`, `#+=`: the words on function keys.
    static let functionFont = UIFont.systemFont(ofSize: 16, weight: .regular)

    /// Shift, delete, globe, the builder key, return.
    static let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .light)
}
