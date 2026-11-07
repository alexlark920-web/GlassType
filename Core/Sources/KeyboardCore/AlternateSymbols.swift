import Foundation

extension KeyboardLanguage {
    /// Extra symbols precede language variants, making a stationary hold useful.
    /// Disabling extra symbols preserves accents and language-specific letters.
    public func holdAlternatives(for key: String, symbolsEnabled: Bool) -> [String] {
        let base = key.lowercased()
        let variants = alternatives(for: base)
        guard symbolsEnabled else { return variants }
        let punctuation = [
            ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "[", "]"],
            ["@", "#", currencySymbol, "%", "&", "-", "+", "(", ")", "/", "="],
            ["*", "\"", "'", ":", ";", "!", "?", "…", ","]
        ]
        if base == "$" { return ["€", "₽", "₴"] + variants }
        for (row, keys) in rows.enumerated() {
            if let column = keys.firstIndex(of: base) {
                let symbol = punctuation[row][column]
                if symbol == "$" { return ["$", "€", "₽", "₴"] }
                return [symbol] + variants.filter { $0 != symbol }
            }
        }
        return variants
    }
    private var currencySymbol: String {
        switch self {
        case .english: return "$"
        case .russian: return "$"
        case .ukrainian: return "$"
        }
    }
}
