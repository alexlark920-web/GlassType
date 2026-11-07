import Foundation

/// Produces a small, language-scoped candidate set from the bundled lexicon
/// and explicit user dictionary. It never scans text outside the supplied context.
public struct CandidateGenerator {
    public init() {}

    public func candidates(prefix: String, language: KeyboardLanguage,
                           personalLexicon: PersonalLexicon,
                           includeProfanity: Bool = false,
                           limit: Int = 24) -> [String] {
        let key = prefix.lowercased()
        guard (1...24).contains(key.count), limit > 0 else { return [] }
        var result: [String] = []
        result.reserveCapacity(min(limit, 24))
        var seen = Set<String>()
        for word in personalLexicon.completions(for: key, limit: 8) +
            OfflineLexicon.completions(prefix: key, language: language, limit: limit,
                                       cachedOnly: true, includeProfanity: includeProfanity) {
            let normalized = word.lowercased()
            guard normalized.hasPrefix(key), normalized != key,
                  includeProfanity || !SupplementalVocabulary.isProfanity(normalized, language: language),
                  seen.insert(normalized).inserted else { continue }
            result.append(word)
            if result.count == limit { break }
        }
        return result
    }
}
