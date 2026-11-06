import Foundation

public enum KeyboardLanguage: String, CaseIterable, Codable {
    case english = "en", russian = "ru", ukrainian = "uk"
    public var title: String { switch self { case .english: return "English"; case .russian: return "Русский"; case .ukrainian: return "Українська" } }
    public var rows: [[String]] {
        let rows: [String]
        switch self {
        case .english: rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
        case .russian: rows = ["йцукенгшщзхъ", "фывапролджэ", "ячсмитьбю"]
        case .ukrainian: rows = ["йцукенгшщзхї", "фівапролджє", "ячсмитьбю"]
        }
        return rows.map { $0.map(String.init) }
    }
    public func alternatives(for key: String) -> [String] {
        let common = ["е": ["ё"], "г": ["ґ"], "ь": ["ъ"], "и": ["і", "ї"], "a": ["á", "à", "ä", "â"], "e": ["é", "è", "ë", "ê"], "i": ["í", "ï", "î"], "o": ["ó", "ö", "ô"], "u": ["ú", "ü", "û"], "n": ["ñ"], ".": [",", "?", "!", ":", ";", "…"], "'": ["’", "ʼ"]]
        return common[key] ?? []
    }
}
public enum ShiftState: Equatable { case off, once, locked }
public struct InputState {
    public var language: KeyboardLanguage
    public private(set) var shift: ShiftState = .once
    public var symbols = false
    private var lastShift: TimeInterval?
    public init(language: KeyboardLanguage = .english) { self.language = language }
    public mutating func tapShift(at time: TimeInterval) {
        if let last = lastShift, time - last >= 0, time - last < 0.32 { shift = .locked; lastShift = nil }
        else { shift = shift == .off ? .once : .off; lastShift = time }
    }
    public mutating func inserted(_ text: String) -> String {
        let result = shift == .off ? text : text.uppercased()
        if shift == .once { shift = .off }
        lastShift = nil
        return result
    }
    public mutating func nextLanguage(enabled: [KeyboardLanguage]) {
        guard !enabled.isEmpty else { return }
        let index = enabled.firstIndex(of: language) ?? -1
        language = enabled[(index + 1) % enabled.count]
    }
    public mutating func synchronize(context: String?, autoCapitalization: Bool) {
        guard shift != .locked, autoCapitalization, let context else { return }
        if context.isEmpty || context.hasSuffix("
") || [". ", "! ", "? "].contains(where: context.hasSuffix) { shift = .once }
    }
}
public protocol SuggestionProvider {
    func suggestions(context: String, language: KeyboardLanguage) -> [String]
}
/// Bounded local prefix lookup. No learning, persistence or automatic replacement.
public struct LocalSuggestionProvider: SuggestionProvider {
    public init() {}
    public func suggestions(context: String, language: KeyboardLanguage) -> [String] {
        guard let last = context.last, last.isLetter else { return [] }
        let prefix = String(context.suffix(64).reversed().prefix(while: { $0.isLetter }).reversed()).lowercased()
        let words: [String]
        switch language {
        case .english: words = ["hello", "help", "here", "thanks", "thank", "today", "tomorrow", "please", "good", "great"]
        case .russian: words = ["привет", "приветствую", "спасибо", "сегодня", "завтра", "пожалуйста", "хорошо"]
        case .ukrainian: words = ["привіт", "привітання", "дякую", "сьогодні", "завтра", "будь", "добре"]
        }
        return Array(words.filter { $0.hasPrefix(prefix) && $0 != prefix }.prefix(3))
    }
    public static func trailingWord(in context: String) -> String {
        String(context.reversed().prefix(while: { $0.isLetter }).reversed())
    }
}
