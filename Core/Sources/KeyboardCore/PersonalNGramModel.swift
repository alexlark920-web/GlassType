import Foundation
import CryptoKit

/// A compact, per-language next-word model. It stores only aggregated counts
/// for one- and two-word contexts; context text itself is never persisted.
public struct PersonalNGramModel: Codable, Equatable {
    private var counts: [String: [String: Int]] = [:]

    private enum CodingKeys: String, CodingKey { case counts }

    public init() {}

    public var contextCount: Int { counts.count }

    /// Learn a completed word from the immediately preceding context.
    /// Callers must exclude secure fields and should only call at word commit.
    public mutating func observe(context: String, nextWord: String, language: KeyboardLanguage) {
        let word = Self.normalizeWord(nextWord)
        guard (1...24).contains(word.count), word.allSatisfy(\.isLetter),
              let contexts = Self.contexts(in: context), !contexts.isEmpty else { return }

        for tokens in contexts {
            let key = Self.contextKey(tokens, language: language)
            var row = counts[key] ?? [:]
            row[word] = min(1_000, (row[word] ?? 0) + 1)
            if row.count > Self.maximumWordsPerContext {
                let least = row.keys.min {
                    let left = row[$0] ?? 0, right = row[$1] ?? 0
                    return left == right ? $0 > $1 : left < right
                }
                if let least { row.removeValue(forKey: least) }
            }
            counts[key] = row
        }
        if counts.count > Self.maximumContexts {
            let least = counts.keys.min {
                let left = counts[$0]?.values.reduce(0, +) ?? 0
                let right = counts[$1]?.values.reduce(0, +) ?? 0
                return left == right ? $0 > $1 : left < right
            }
            if let least { counts.removeValue(forKey: least) }
        }
    }

    /// Rank a small candidate set using smoothed unigram-history and trigram
    /// counts. A missing profile contributes zero, leaving dictionary order intact.
    public func score(_ candidate: String, after context: String, language: KeyboardLanguage) -> Double {
        let word = Self.normalizeWord(candidate)
        guard let contexts = Self.contexts(in: context), !contexts.isEmpty else { return 0 }
        var score = 0.0
        for (index, tokens) in contexts.enumerated() {
            guard let row = counts[Self.contextKey(tokens, language: language)], !row.isEmpty else { continue }
            let total = row.values.reduce(0, +)
            let value = Double(row[word] ?? 0)
            let probability = (value + 0.5) / (Double(total) + 0.5 * Double(row.count + 1))
            score += (index == 0 ? 1.0 : 1.45) * log(probability)
        }
        return score
    }

    public func nextWords(after context: String, language: KeyboardLanguage,
                          prefix: String = "", limit: Int = 3) -> [String] {
        guard limit > 0, let contexts = Self.contexts(in: context), !contexts.isEmpty else { return [] }
        let keyPrefix = Self.normalizeWord(prefix)
        var candidates = Set<String>()
        for tokens in contexts {
            guard let row = counts[Self.contextKey(tokens, language: language)] else { continue }
            for word in row.keys {
                if keyPrefix.isEmpty || word.hasPrefix(keyPrefix) { candidates.insert(word) }
            }
        }
        return candidates.sorted {
            let left = score($0, after: context, language: language)
            let right = score($1, after: context, language: language)
            return left == right ? $0 < $1 : left > right
        }.prefix(limit).map { $0 }
    }

    /// Bound and validate data loaded from the extension's local preferences.
    public func sanitized() -> PersonalNGramModel {
        var result = PersonalNGramModel()
        for key in counts.keys.sorted().prefix(Self.maximumContexts) {
            guard key.count == 32, key.allSatisfy(\.isHexDigit), let row = counts[key] else { continue }
            let entries = row.keys.sorted {
                let left = row[$0] ?? 0, right = row[$1] ?? 0
                return left == right ? $0 < $1 : left > right
            }.prefix(Self.maximumWordsPerContext)
            var clean: [String: Int] = [:]
            for word in entries {
                let normalized = Self.normalizeWord(word)
                guard (1...24).contains(normalized.count), normalized.allSatisfy(\.isLetter),
                      let value = row[word], value > 0 else { continue }
                clean[normalized] = min(1_000, value)
            }
            if !clean.isEmpty { result.counts[key] = clean }
        }
        return result
    }

    private static let maximumContexts = 128
    private static let maximumWordsPerContext = 8

    private static func contexts(in text: String) -> [[String]]? {
        let bounded = String(text.suffix(192)).lowercased()
        let words = bounded.split(whereSeparator: { !$0.isLetter }).map(String.init).filter { (1...24).contains($0.count) }
        guard let last = words.last else { return [["<s>"]] }
        if words.count > 1 { return [[words[words.count - 2], last], [last]] }
        return [[last]]
    }

    private static func contextKey(_ words: [String], language: KeyboardLanguage) -> String {
        let normalized = language.rawValue + "\u{0}" + words.map(normalizeWord).joined(separator: "\u{1f}")
        return SHA256.hash(data: Data(normalized.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizeWord(_ word: String) -> String {
        word.precomposedStringWithCanonicalMapping.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "ʼ", with: "'")
    }
}
