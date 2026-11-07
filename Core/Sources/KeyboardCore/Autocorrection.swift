import Foundation

/// Conservative on-device correction policy. System dictionary candidates are
/// supplied by the UIKit adapter; common typos remain available without it.
public struct AutocorrectionEngine {
    public init() {}
    public func replacement(for word: String, language: KeyboardLanguage,
                            candidates: [String] = [], isKnownWord: Bool = false) -> String? {
        guard !isKnownWord, (3...24).contains(word.count), word.allSatisfy(\.isLetter),
              !word.allSatisfy(\.isUppercase) else { return nil }
        let lowercase = word.lowercased()
        let sentenceCase = word == lowercase.capitalized
        guard word == lowercase || sentenceCase, isNative(lowercase, language: language) else { return nil }
        let typos: [String: String]
        switch language {
        case .english:
            typos = ["teh": "the", "hte": "the", "adn": "and", "taht": "that",
                     "thsi": "this", "helo": "hello", "helllo": "hello", "woudl": "would",
                     "coudl": "could", "shoudl": "should", "becuase": "because", "recieve": "receive",
                     "tommorow": "tomorrow", "thnaks": "thanks", "pleaes": "please"]
        case .russian:
            typos = ["првиет": "привет", "привте": "привет", "пирвет": "привет",
                     "спсибо": "спасибо", "спаисбо": "спасибо", "спасбио": "спасибо",
                     "пожалуста": "пожалуйста", "пожлауйста": "пожалуйста", "сегодян": "сегодня",
                     "заврта": "завтра", "хоршо": "хорошо",
                     "здраствуйте": "здравствуйте"]
        case .ukrainian:
            typos = ["првиіт": "привіт", "пирвіт": "привіт", "привті": "привіт",
                     "дякуб": "дякую", "дякуую": "дякую", "дякюу": "дякую",
                     "сьогдні": "сьогодні", "сьогодін": "сьогодні", "заврта": "завтра",
                     "добер": "добре", "ласкаа": "ласка"]
        }
        let result: String?
        if let explicit = typos[lowercase] {
            result = explicit
        } else {
            guard lowercase.count >= 4, candidates.count <= 8 else { return nil }
            let matches = Set(candidates.map { $0.lowercased() }.filter {
                $0 != lowercase && $0.allSatisfy(\.isLetter) && isNative($0, language: language) &&
                Self.isSingleEdit(lowercase, $0)
            })
            result = matches.count == 1 ? matches.first : nil
        }
        guard let result else { return nil }
        return sentenceCase ? result.capitalized : result
    }
    /// Excludes addresses, identifiers, apostrophes and tokens containing digits.
    public static func trailingPlainWord(in context: String) -> String? {
        guard let last = context.last, last.isLetter else { return nil }
        let suffix = String(context.suffix(96))
        guard let token = suffix.split(whereSeparator: { $0.isWhitespace }).last else { return nil }
        let word = LocalSuggestionProvider.trailingWord(in: String(token))
        guard (3...24).contains(word.count) else { return nil }
        let leading = token.dropLast(word.count)
        let opening = Set("([{«“\"")
        guard leading.allSatisfy({ opening.contains($0) }) else { return nil }
        return word
    }
    private func isNative(_ word: String, language: KeyboardLanguage) -> Bool {
        let alphabet: String
        switch language {
        case .english: alphabet = "abcdefghijklmnopqrstuvwxyzáàäâéèëêíïîóöôúüûñ"
        case .russian: alphabet = "абвгдеёжзийклмнопрстуфхцчшщъыьэюя"
        case .ukrainian: alphabet = "абвгґдеєжзиіїйклмнопрстуфхцчшщьюя"
        }
        let letters = Set(alphabet)
        return word.allSatisfy { letters.contains($0) }
    }
    /// Exactly one insertion, deletion, substitution or adjacent transposition.
    public static func isSingleEdit(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs), b = Array(rhs)
        guard abs(a.count - b.count) <= 1, a != b else { return false }
        if a.count == b.count {
            let indices = a.indices.filter { a[$0] != b[$0] }
            if indices.count == 1 { return true }
            return indices.count == 2 && indices[1] == indices[0] + 1 &&
                a[indices[0]] == b[indices[1]] && a[indices[1]] == b[indices[0]]
        }
        let shorter = a.count < b.count ? a : b
        let longer = a.count < b.count ? b : a
        var i = 0, j = 0, skipped = false
        while i < shorter.count && j < longer.count {
            if shorter[i] == longer[j] { i += 1; j += 1 }
            else if !skipped { skipped = true; j += 1 }
            else { return false }
        }
        return true
    }
}

/// A bounded snapshot ensures Backspace only undoes a correction at its cursor.
public struct CorrectionUndo {
    public let original: String
    public let replacement: String
    public let delimiter: String
    private let before: String
    private let after: String?
    private let document: String
    public init(original: String, replacement: String, delimiter: String,
                before: String, after: String?, document: String) {
        self.original = original; self.replacement = replacement; self.delimiter = delimiter
        self.before = String(before.suffix(192)); self.after = after.map { String($0.prefix(32)) }
        self.document = document
    }
    public func matches(before: String?, after: String?, document: String, hasSelection: Bool) -> Bool {
        guard !hasSelection, self.document == document, let before else { return false }
        return String(before.suffix(192)) == self.before &&
            after.map({ String($0.prefix(32)) }) == self.after && before.hasSuffix(replacement + delimiter)
    }
}
