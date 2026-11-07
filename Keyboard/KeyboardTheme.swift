import UIKit

/// Semantic tint for native Liquid Glass caps on iOS 26+, with a translucent
/// fallback on older systems and an opaque accessibility appearance.
struct KeyboardTheme {
    let key: UIColor
    let function: UIColor
    let spacebar: UIColor
    let accent: UIColor
    let foreground: UIColor
    let radius: CGFloat
    private static let keycap = UIColor { traits in
        let dark = traits.userInterfaceStyle == .dark
        let contrast = traits.accessibilityContrast == .high
        return UIColor(white: dark ? (contrast ? 0.34 : 0.28) : 0.96,
                       alpha: contrast ? 0.96 : (dark ? 0.82 : 0.86))
    }
    private static let spacecap = UIColor { traits in
        let dark = traits.userInterfaceStyle == .dark
        let contrast = traits.accessibilityContrast == .high
        return UIColor(white: dark ? (contrast ? 0.34 : 0.28) : 0.88,
                       alpha: contrast ? 0.96 : (dark ? 0.82 : 0.90))
    }
    static let material = KeyboardTheme(key: keycap, function: keycap, spacebar: spacecap,
                                        accent: .systemIndigo,
                                        foreground: .label, radius: 7.5)
}
