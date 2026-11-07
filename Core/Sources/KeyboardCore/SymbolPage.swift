import Foundation

public enum SymbolPage: CaseIterable, Equatable {
    case numbers, extended
    public var switchTitle: String { self == .numbers ? "#*=" : "123" }
    public var next: SymbolPage { self == .numbers ? .extended : .numbers }
    public var rows: [[String]] {
        switch self {
        case .numbers:
            return [Array("1234567890").map(String.init),
                    ["@", "#", "$", "%", "&", "-", "+", "(", ")", "/"],
                    ["*", "\"", "'", ":", ";", "!", "?"]]
        case .extended:
            return [["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
                    ["_", "\\", "|", "~", "<", ">", "£", "¥"],
                    ["•", "√", "π", "÷", "×", "°"]]
        }
    }

    public func holdAlternatives(for key: String) -> [String] {
        let powers = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
                      "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"]
        if let power = powers[key] { return [power] }
        if key == "$" { return ["€", "₽", "₴"] }
        return []
    }
}
