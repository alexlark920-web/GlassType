import Foundation

/// Explicit user entries only. No automatic learning or network access.
public struct PersonalLexicon: Codable, Equatable {
    public var replacements: [String: String]
    public var excludedWords: [String]
    public var knownWords: [String]

    public init(replacements: [String: String] = [:], excludedWords: [String] = [], knownWords: [String] = []) {
        self.replacements = replacements
        self.excludedWords = excludedWords
        self.knownWords = knownWords
    }

    private enum CodingKeys: String, CodingKey { case replacements, excludedWords, knownWords }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        replacements = try values.decodeIfPresent([String: String].self, forKey: .replacements) ?? [:]
        excludedWords = try values.decodeIfPresent([String].self, forKey: .excludedWords) ?? []
        knownWords = try values.decodeIfPresent([String].self, forKey: .knownWords) ?? []
    }
    /// Apply after decoding and after editing. Deterministic limits bound storage.
    public func sanitized() -> PersonalLexicon {
        var pairs: [String: String] = [:]
        for key in replacements.keys.sorted().prefix(200) {
            let normalized = Self.normalize(key)
            let value = (replacements[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, normalized.count <= 64,
                  !normalized.contains(where: { $0.isWhitespace }),
                  !value.isEmpty, value.count <= 128,
                  !value.contains(where: { $0.isNewline || $0.asciiValue.map { $0 < 32 } == true }) else { continue }
            pairs[normalized] = value
        }
        let excluded = Set(excludedWords.prefix(400).map(Self.normalize).filter {
            !$0.isEmpty && $0.count <= 64 && !$0.contains(where: { $0.isWhitespace })
        })
        var seen = Set<String>()
        let words = knownWords.prefix(500).compactMap { value -> String? in
            let word = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = Self.normalize(word)
            guard (2...64).contains(word.count), word.allSatisfy({ $0.isLetter || "'’ʼ-".contains($0) }),
                  seen.insert(key).inserted else { return nil }
            return word
        }
        return PersonalLexicon(replacements: pairs, excludedWords: Array(excluded).sorted(), knownWords: words)
    }

    public func containsKnownWord(_ word: String) -> Bool {
        let key = Self.normalize(word)
        return !key.isEmpty && knownWords.contains { Self.normalize($0) == key }
    }

    public func completions(for prefix: String, limit: Int = 3) -> [String] {
        let key = Self.normalize(prefix)
        guard !key.isEmpty, limit > 0 else { return [] }
        return knownWords.filter { candidate in
            let normalized = Self.normalize(candidate)
            return normalized != key && normalized.hasPrefix(key) && !excludes(candidate)
        }.prefix(limit).map { $0 }
    }

    public mutating func addKnownWord(_ word: String) {
        knownWords.append(word)
        self = sanitized()
    }
    public func excludes(_ word: String) -> Bool {
        let key = Self.normalize(word)
        return excludedWords.contains { Self.normalize($0) == key }
    }
    /// Explicit exclusions win over replacement entries. User-supplied mixed
    /// case is retained; sentence case only promotes a fully lowercase value.
    public func replacement(for word: String) -> String? {
        guard !excludes(word) else { return nil }
        let key = Self.normalize(word)
        guard !key.isEmpty else { return nil }
        let storedKey = replacements[key] == nil ? replacements.keys.sorted().first(where: { Self.normalize($0) == key }) : key
        guard let storedKey, let value = replacements[storedKey], !value.isEmpty else { return nil }
        if value == value.lowercased() {
            if word.count > 1, word.allSatisfy(\.isUppercase) { return value.uppercased() }
            if word.first?.isUppercase == true, let first = value.first {
                return String(first).uppercased() + value.dropFirst()
            }
        }
        return value
    }
    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping.lowercased()
    }
}
