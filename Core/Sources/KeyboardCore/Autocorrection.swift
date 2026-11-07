import Foundation

/// Conservative on-device correction policy. System dictionary candidates are
/// supplied by the UIKit adapter; common typos remain available without it.
public struct AutocorrectionEngine {
    public struct Candidate {
        public let word: String
        public let frequencyRank: Int?
        public init(_ word: String, frequencyRank: Int? = nil) {
            self.word = word; self.frequencyRank = frequencyRank
        }
    }
    public init() {}
    /// Frequency and keyboard-neighbour costs are separate, explicit heuristics.
    /// Unlike the unique-candidate API below, this can choose a dominant local
    /// word from several dictionary guesses. Near ties deliberately stay intact.
    public func rankedReplacement(for word: String, language: KeyboardLanguage,
                                  candidates: [Candidate], isKnownWord: Bool = false) -> String? {
        guard !isKnownWord else { return nil }
        if let explicit = replacement(for: word, language: language) { return explicit }
        let lower = word.lowercased()
        guard (4...24).contains(lower.count), word == lower || word == lower.capitalized,
              !word.allSatisfy(\.isUppercase), lower.allSatisfy(\.isLetter), isNative(lower, language: language) else { return nil }
        var matches: [String: Candidate] = [:]
        for candidate in candidates.prefix(32) {
            let text = candidate.word.lowercased()
            guard text != lower, text.allSatisfy(\.isLetter), isNative(text, language: language), Self.isSingleEdit(lower, text) else { continue }
            let rank = candidate.frequencyRank.flatMap { $0 >= 0 ? $0 : nil }
            if let existing = matches[text] {
                if let rank, rank < (existing.frequencyRank ?? Int.max) { matches[text] = Candidate(text, frequencyRank: rank) }
            } else { matches[text] = Candidate(text, frequencyRank: rank) }
        }
        let ranked = matches.map { text, candidate -> (word: String, score: Double) in
            let prior = candidate.frequencyRank.map { 0.15 * log(Double($0) + 16) } ?? 1.35
            return (text, editCost(lower, text, language: language) + prior)
        }.sorted { $0.score == $1.score ? $0.word < $1.word : $0.score < $1.score }
        guard let best = ranked.first, best.score <= 2.65 else { return nil }
        if ranked.count > 1, ranked[1].score - best.score < 0.18 { return nil }
        return word == lower.capitalized ? best.word.capitalized : best.word
    }

    private func editCost(_ a: String, _ b: String, language: KeyboardLanguage) -> Double {
        let source = Array(a), target = Array(b)
        guard source.count == target.count else { return 0.80 }
        let differences = source.indices.filter { source[$0] != target[$0] }
        if differences.count == 2 { return 0.55 } // adjacent transposition
        guard let i = differences.first else { return 0 }
        func position(_ character: Character) -> (Double, Double)? {
            let rows = language.rows
            let width = rows.map(\.count).max() ?? 1
            for (row, keys) in rows.enumerated() {
                if let column = keys.firstIndex(of: String(character)) {
                    return (Double(column) + Double(width - keys.count) / 2, Double(row))
                }
            }
            return nil
        }
        guard let x = position(source[i]), let y = position(target[i]) else { return 0.95 }
        return hypot(x.0 - y.0, x.1 - y.1) <= 1.5 ? 0.65 : 0.95
    }
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
