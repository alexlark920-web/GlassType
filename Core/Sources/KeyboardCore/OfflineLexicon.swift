import Foundation

/// Frequency-ranked local resources. Cache construction is serialized; returned
/// Swift arrays/dictionaries are immutable snapshots safe for background decoding.
public enum OfflineLexicon {
    private final class DataSet {
        let words: [String]
        let ranks: [String: Int]
        init(language: KeyboardLanguage) {
            guard let url = Bundle.module.url(forResource: "lexicon_" + language.rawValue, withExtension: "txt"),
                  let content = try? String(contentsOf: url, encoding: .utf8) else {
                words = []; ranks = [:]; return
            }
            var list: [String] = []
            var index: [String: Int] = [:]
            list.reserveCapacity(20_000); index.reserveCapacity(20_000)
            for line in content.split(whereSeparator: { $0.isNewline }).prefix(30_000) {
                let word = String(line)
                guard (2...24).contains(word.count), index[word] == nil else { continue }
                index[word] = list.count; list.append(word)
            }
            words = list; ranks = index
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
    public static func words(language: KeyboardLanguage) -> [String] { data(for: language).words }
    public static func contains(_ word: String, language: KeyboardLanguage) -> Bool {
        data(for: language).ranks[normalized(word)] != nil
    }
    public static func frequencyIndex(word: String, language: KeyboardLanguage) -> Int? {
        data(for: language).ranks[normalized(word)]
    }
    public static func correctionCandidates(_ word: String, language: KeyboardLanguage, limit: Int = 8) -> [String] {
        correctionCandidates(for: word, language: language, limit: limit)
    }
    /// Generate edit-distance-one words and use O(1) dictionary membership.
    /// This avoids scanning every word or retaining a large deletion index.
    public static func correctionCandidates(for word: String, language: KeyboardLanguage, limit: Int = 8) -> [String] {
        let key = normalized(word)
        guard (2...24).contains(key.count), limit > 0 else { return [] }
        let dictionary = data(for: language)
        guard dictionary.ranks[key] == nil else { return [] }
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
