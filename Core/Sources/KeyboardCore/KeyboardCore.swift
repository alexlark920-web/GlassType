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
    public var symbolPage: SymbolPage = .numbers
    private var lastShift: TimeInterval?
    private var automaticShift = true
    public init(language: KeyboardLanguage = .english) { self.language = language }
    public mutating func tapShift(at time: TimeInterval) {
        automaticShift = false
        if let last = lastShift, time - last >= 0, time - last < 0.32 { shift = .locked; lastShift = nil }
        else { shift = shift == .off ? .once : .off; lastShift = time }
    }
    public mutating func inserted(_ text: String) -> String {
        guard !symbols else { lastShift = nil; return text }
        let result = shift == .off ? text : text.uppercased()
        if shift == .once && text.contains(where: { $0.isLetter }) { shift = .off; automaticShift = false }
        lastShift = nil
        return result
    }
    /// One-shot shift affects one letter in a completed word; Caps Lock affects
    /// the whole word. Used by glide and explicit suggestion acceptance.
    public mutating func insertedWord(_ text: String) -> String {
        guard !symbols else { lastShift = nil; return text }
        let originalShift = shift
        _ = inserted(text)
        if originalShift == .locked { return text.uppercased() }
        guard originalShift == .once, let index = text.firstIndex(where: { $0.isLetter }) else { return text }
        var result = text
        result.replaceSubrange(index...index, with: String(text[index]).uppercased())
        return result
    }
    public mutating func nextLanguage(enabled: [KeyboardLanguage]) {
        cycleLanguage(enabled: enabled, direction: .next)
    }
    public mutating func cycleLanguage(enabled: [KeyboardLanguage], direction: LanguageDirection) {
        guard let first = enabled.first else { return }
        guard let index = enabled.firstIndex(of: language) else { language = first; return }
        let offset = direction == .next ? 1 : -1
        language = enabled[(index + offset + enabled.count) % enabled.count]
    }
    public mutating func synchronize(context: String?, autoCapitalization: Bool, fieldIsEmpty: Bool = false) {
        // hasText=false is distinct from missing proxy context. Never interpret
        // nil alone as an empty message, including at a mid-document caret.
        guard shift != .locked else { return }
        if !autoCapitalization && automaticShift { shift = .off; automaticShift = false }
        guard let context = fieldIsEmpty ? "" : context else {
            if automaticShift { shift = .off; automaticShift = false }
            return
        }
        let needed = autoCapitalization && SentenceCapitalization.shouldCapitalize(contextBeforeInput: context)
        if needed && shift == .off { shift = .once; automaticShift = true }
        else if !needed && automaticShift { shift = .off; automaticShift = false }
    }

}
public protocol SuggestionProvider {
    func suggestions(context: String, language: KeyboardLanguage) -> [String]
}
/// Frequency-ranked offline prefix lookup. No learning, persistence or replacement.
public struct LocalSuggestionProvider: SuggestionProvider {
    private let cachedOnly: Bool
    public init(cachedOnly: Bool = false) { self.cachedOnly = cachedOnly }
    public func suggestions(context: String, language: KeyboardLanguage) -> [String] {
        guard let last = context.last, last.isLetter else { return [] }
        let prefix = String(context.suffix(64).reversed().prefix(while: { $0.isLetter }).reversed()).lowercased()
        return OfflineLexicon.completions(prefix: prefix, language: language, cachedOnly: cachedOnly)
    }

    public static func trailingWord(in context: String) -> String {
        String(context.reversed().prefix(while: { $0.isLetter }).reversed())
    }
}
