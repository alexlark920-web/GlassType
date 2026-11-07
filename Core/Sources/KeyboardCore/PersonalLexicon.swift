import Foundation

/// Explicit user entries only. No automatic learning or network access.
public struct PersonalLexicon: Codable, Equatable {
    public var replacements: [String: String]
    public var excludedWords: [String]
    public init(replacements: [String: String] = [:], excludedWords: [String] = []) {
        self.replacements = replacements
        self.excludedWords = excludedWords
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
        return PersonalLexicon(replacements: pairs, excludedWords: Array(excluded).sorted())
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
