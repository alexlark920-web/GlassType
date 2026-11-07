import Foundation

/// Frequency-ranked local resources. Cache construction is serialized; returned
/// Swift arrays/dictionaries are immutable snapshots safe for background decoding.
public enum OfflineLexicon {
    private final class DataSet {
        let words: [String]
        let ranks: [String: Int]
        let prefixes: [String: [Int32]]
        init(language: KeyboardLanguage) {
            guard let url = Bundle.module.url(forResource: "lexicon_" + language.rawValue, withExtension: "txt"),
                  let content = try? String(contentsOf: url, encoding: .utf8) else {
                words = []; ranks = [:]; prefixes = [:]; return
            }
            var list: [String] = []
            var index: [String: Int] = [:]
            var groups: [String: [Int32]] = [:]
            list.reserveCapacity(31_000); index.reserveCapacity(31_000); groups.reserveCapacity(1000)
            let bundled = content.split(whereSeparator: { $0.isNewline }).prefix(31_000).map { String($0) }
            for word in (bundled + SupplementalVocabulary.words(for: language)) {
                guard (2...24).contains(word.count), index[word] == nil else { continue }
                let position = Int32(list.count)
                groups[String(word.prefix(1)), default: []].append(position)
                groups[String(word.prefix(2)), default: []].append(position)
                index[word] = list.count; list.append(word)
            }
            words = list; ranks = index; prefixes = groups
        }
    }
    public static var licenseNotice: String {
        ["Dictionary-Attribution", "CC-BY-SA-4.0", "MPL-1.1"].compactMap { name in
            Bundle.module.url(forResource: name, withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        }.joined(separator: "\n\n")
    }
    private static let lock = NSLock()
    private static var cache: [KeyboardLanguage: DataSet] = [:]
    private static var cacheOrder: [KeyboardLanguage] = []
    private static func data(for language: KeyboardLanguage) -> DataSet {
        lock.lock(); defer { lock.unlock() }
        if let existing = cache[language] { return existing }
        let result = DataSet(language: language)
        // One active language plus an in-flight language switch; decoder models
        // may retain their own immutable word-array snapshot.
        if cacheOrder.count >= 2, let oldest = cacheOrder.first {
            cache.removeValue(forKey: oldest); cacheOrder.removeFirst()
        }
        cache[language] = result; cacheOrder.append(language)
        return result
    }
    private static func preparedData(for language: KeyboardLanguage) -> DataSet? {
        // UI callers can skip a suggestion frame instead of waiting on I/O.
        guard lock.try() else { return nil }
        defer { lock.unlock() }
        return cache[language]
    }
    public static func isPrepared(language: KeyboardLanguage) -> Bool { preparedData(for: language) != nil }
    public static func words(language: KeyboardLanguage) -> [String] { data(for: language).words }
    public static func completions(prefix: String, language: KeyboardLanguage, limit: Int = 3, cachedOnly: Bool = false, includeProfanity: Bool = false) -> [String] {
        let key = normalized(prefix)
        guard (1...24).contains(key.count), limit > 0 else { return [] }
        guard let dictionary = cachedOnly ? preparedData(for: language) : data(for: language) else { return [] }
        let positions = dictionary.prefixes[String(key.prefix(2))] ?? []
        var result: [String] = []; result.reserveCapacity(min(8, limit))
        if key.count >= 3 {
            for word in SupplementalVocabulary.words(for: language) where word.hasPrefix(key) && word != key && (includeProfanity || !SupplementalVocabulary.isProfanity(word, language: language)) {
                result.append(word)
                if result.count == min(8, limit) { return result }
            }
        }
        for position in positions {
            let word = dictionary.words[Int(position)]
            if word != key && word.hasPrefix(key) && !result.contains(word) && (includeProfanity || !SupplementalVocabulary.isProfanity(word, language: language)) {
                result.append(word)
                if result.count == min(8, limit) { break }
            }
        }
        return result
    }
    public struct SpellingCheck {
        public let known: Bool
        public let candidates: [String]
        public let rankedCandidates: [AutocorrectionEngine.Candidate]
    }
    /// One immutable snapshot; never waits for corpus construction on a UI call.
    public static func preparedCheck(_ word: String, language: KeyboardLanguage, includeProfanity: Bool = false) -> SpellingCheck? {
        guard let dictionary = preparedData(for: language) else { return nil }
        let known = dictionary.ranks[normalized(word)] != nil
        let words = known ? [] : candidates(for: word, language: language, dictionary: dictionary, limit: 16)
            .filter { includeProfanity || !SupplementalVocabulary.isProfanity($0, language: language) }
        return SpellingCheck(known: known, candidates: words,
                             rankedCandidates: words.map { .init($0, frequencyRank: dictionary.ranks[$0]) })
    }
    public static func contains(_ word: String, language: KeyboardLanguage) -> Bool {
        data(for: language).ranks[normalized(word)] != nil
    }
    public static func frequencyIndex(word: String, language: KeyboardLanguage) -> Int? {
        data(for: language).ranks[normalized(word)]
    }
    public static func correctionCandidates(_ word: String, language: KeyboardLanguage, limit: Int = 8, includeProfanity: Bool = false) -> [String] {
        correctionCandidates(for: word, language: language, limit: limit, includeProfanity: includeProfanity)
    }
    /// Generate edit-distance-one words and use O(1) dictionary membership.
    /// This avoids scanning every word or retaining a large deletion index.
    public static func correctionCandidates(for word: String, language: KeyboardLanguage, limit: Int = 8, includeProfanity: Bool = false) -> [String] {
        candidates(for: word, language: language, dictionary: data(for: language), limit: limit)
            .filter { includeProfanity || !SupplementalVocabulary.isProfanity($0, language: language) }
    }
    private static func candidates(for word: String, language: KeyboardLanguage, dictionary: DataSet, limit: Int) -> [String] {
        let key = normalized(word)
        guard (2...24).contains(key.count), limit > 0, dictionary.ranks[key] == nil else { return [] }
        let letters: [Character]
        switch language {
        case .english: letters = Array("abcdefghijklmnopqrstuvwxyz'-")
        case .russian: letters = Array("абвгдеёжзийклмнопрстуфхцчшщъыьэюя'-")
        case .ukrainian: letters = Array("абвгґдеєжзиіїйклмнопрстуфхцчшщьюя'-")
        }
        let source = Array(key)
        guard source.allSatisfy({ letters.contains($0) }) else { return [] }
        var matches = Set<String>()
        func consider(_ characters: [Character]) {
            let candidate = String(characters)
            if candidate != key, dictionary.ranks[candidate] != nil { matches.insert(candidate) }
        }
        for index in source.indices {
            var removed = source; removed.remove(at: index); consider(removed)
            if index + 1 < source.count {
                var swapped = source; swapped.swapAt(index, index + 1); consider(swapped)
            }
            for letter in letters where letter != source[index] {
                var replaced = source; replaced[index] = letter; consider(replaced)
            }
        }
        if source.count < 24 {
            for index in 0...source.count {
                for letter in letters {
                    var inserted = source; inserted.insert(letter, at: index); consider(inserted)
                }
            }
        }
        return Array(matches.sorted {
            let a = dictionary.ranks[$0] ?? Int.max, b = dictionary.ranks[$1] ?? Int.max
            return a == b ? $0 < $1 : a < b
        }.prefix(min(16, limit)))
    }
    private static func normalized(_ word: String) -> String {
        word.precomposedStringWithCanonicalMapping.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "ʼ", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "‑", with: "-")
    }
}
