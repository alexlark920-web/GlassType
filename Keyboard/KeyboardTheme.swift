import UIKit

/// Semantic colors follow explicit theme settings, system appearance and contrast.
/// Thin material is a supported fallback; no unverified iOS 27 glass APIs.
struct KeyboardTheme {
    let key: UIColor
    let function: UIColor
    let accent: UIColor
    let foreground: UIColor
    let radius: CGFloat
    static let material = KeyboardTheme(key: .secondarySystemGroupedBackground,
                                        function: .tertiarySystemFill,
                                        accent: .systemIndigo,
                                        foreground: .label, radius: 10)
}
