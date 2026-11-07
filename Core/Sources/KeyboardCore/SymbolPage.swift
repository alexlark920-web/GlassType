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
}
