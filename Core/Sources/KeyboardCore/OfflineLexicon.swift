import Foundation

/// Memory-mapped local dictionaries. Only the selected language is retained;
/// word strings are materialized only for the glide decoder compatibility API.
public enum OfflineLexicon {
    private final class DataSet: @unchecked Sendable {
        let language: KeyboardLanguage
        let trie: MappedBinaryLexicon?
        let orderedWordData: Data?
        private let rankLock = NSLock()
        private var rankCache: [String: Int] = [:]

        init(language: KeyboardLanguage) {
            self.language = language
            let name = "lexicon_" + language.rawValue
            if let url = Bundle.module.url(forResource: name, withExtension: "trie") {
                trie = try? MappedBinaryLexicon(url: url)
            } else {
                trie = nil
            }
            if let url = Bundle.module.url(forResource: name, withExtension: "txt") {
                orderedWordData = try? Data(contentsOf: url, options: .mappedIfSafe)
            } else {
                orderedWordData = nil
            }
        }

        func words() -> [String] {
            let bundled = orderedWordData.map {
                String(decoding: $0, as: UTF8.self).split(whereSeparator: { $0.isNewline })
                    .prefix(51_000).map { String($0.split(separator: "\t", maxSplits: 1).first ?? $0) }
            } ?? []
            var seen = Set(bundled)
            return bundled + SupplementalVocabulary.words(for: language).filter { seen.insert($0).inserted }
        }

        /// Rank only this small query set by scanning the mapped source list.
        /// It avoids retaining an 80k-entry String/Dictionary index.
        func ranks(for words: [String]) -> [String: Int] {
            guard let orderedWordData, !words.isEmpty else { return [:] }
            rankLock.lock()
            var result = Dictionary(uniqueKeysWithValues: words.compactMap { source -> (String, Int)? in
                let word = normalized(source)
                return rankCache[word].map { (word, $0) }
            })
            rankLock.unlock()
            let missing = words.map(normalized).filter { result[$0] == nil }
            var targets: [UInt64: [(String, [UInt8])]] = [:]
            for word in missing {
                let bytes = Array(word.utf8)
                targets[Self.hash(bytes), default: []].append((word, bytes))
            }
            guard !targets.isEmpty else { return result }
            orderedWordData.withUnsafeBytes { raw in
                guard let bytes = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                var start = 0
                var rank = 0
                for end in 0...raw.count {
                    guard end == raw.count || bytes[end] == 10 else { continue }
                    var wordEnd = end
                    if wordEnd > start, bytes[wordEnd - 1] == 13 { wordEnd -= 1 }
                    if let tab = (start..<wordEnd).first(where: { bytes[$0] == 9 }) { wordEnd = tab }
                    if wordEnd > start {
                        let view = UnsafeBufferPointer(start: bytes + start, count: wordEnd - start)
                        if let candidates = targets[Self.hash(view)] {
                            for (word, target) in candidates where target.count == view.count {
                                if target.withUnsafeBufferPointer({ $0.elementsEqual(view) }) {
                                    result[word] = rank
                                }
                            }
                        }
                        rank += 1
                    }
                    start = end + 1
                }
            }
            let extras = SupplementalVocabulary.words(for: language)
            for (index, word) in extras.enumerated() where result[normalized(word)] == nil {
                result[normalized(word)] = (orderedWordData.count == 0 ? 0 : orderedWordData.splitLinesCount) + index
            }
            rankLock.lock()
            if rankCache.count + result.count > 1_024 { rankCache.removeAll(keepingCapacity: true) }
            rankCache.merge(result) { old, _ in old }
            rankLock.unlock()
            return result
        }

        func completions(prefix: String, limit: Int, includeProfanity: Bool) -> [String] {
            guard limit > 0, let trie else { return [] }
            let key = normalized(prefix)
            var result: [String] = []
            if key.count >= 3 {
                result = SupplementalVocabulary.words(for: language).filter {
                    normalized($0).hasPrefix(key) && normalized($0) != key &&
                        (includeProfanity || !SupplementalVocabulary.isProfanity($0, language: language))
                }
                if result.count >= limit { return Array(result.prefix(limit)) }
            }
            guard trie.findWords(matchingPrefix: key, limit: 1).isEmpty == false else { return result }
            guard let orderedWordData else {
                let mapped = trie.findWords(matchingPrefix: key, limit: limit + 1)
                return (result + mapped.filter { normalized($0) != key }).prefix(limit).map { $0 }
            }
            let prefixBytes = Array(key.utf8)
            var foundRanks: [String: Int] = [:]
            orderedWordData.withUnsafeBytes { raw in
                guard let bytes = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                var start = 0
                var rank = 0
                for end in 0...raw.count {
                    guard end == raw.count || bytes[end] == 10 else { continue }
                    var wordEnd = end
                    if wordEnd > start, bytes[wordEnd - 1] == 13 { wordEnd -= 1 }
                    if let tab = (start..<wordEnd).first(where: { bytes[$0] == 9 }) { wordEnd = tab }
                    if wordEnd - start >= prefixBytes.count,
                       prefixBytes.withUnsafeBufferPointer({ buffer in
                           UnsafeBufferPointer(start: bytes + start, count: buffer.count).starts(with: buffer)
                       }) {
                        let word = String(decoding: UnsafeBufferPointer(start: bytes + start, count: wordEnd - start), as: UTF8.self)
                        if normalized(word) != key,
                           (includeProfanity || !SupplementalVocabulary.isProfanity(word, language: language)),
                           !result.contains(where: { normalized($0) == normalized(word) }),
                           trie.contains(word) {
                            result.append(word)
                            foundRanks[normalized(word)] = rank
                            if result.count >= limit { break }
                        }
                    }
                    rank += 1
                    start = end + 1
                }
            }
            rankLock.lock()
            if rankCache.count + foundRanks.count > 1_024 { rankCache.removeAll(keepingCapacity: true) }
            rankCache.merge(foundRanks) { old, _ in old }
            rankLock.unlock()
            return Array(result.prefix(limit))
        }

        private static func hash(_ bytes: [UInt8]) -> UInt64 {
            bytes.withUnsafeBufferPointer { hash($0) }
        }
        private static func hash(_ bytes: UnsafeBufferPointer<UInt8>) -> UInt64 {
            bytes.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        }
    }

    public static var licenseNotice: String {
        ["Dictionary-Attribution", "CC-BY-SA-4.0", "MPL-1.1"].compactMap { name in
            Bundle.module.url(forResource: name, withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        }.joined(separator: "\n\n")
    }

    private static let lock = NSLock()
    private static var active: DataSet?

    /// Select a language and release the previous mapped resource immediately
    /// when no in-flight caller still holds it.
    public static func activate(language: KeyboardLanguage) {
        lock.lock(); defer { lock.unlock() }
        guard active?.language != language else { return }
        active = DataSet(language: language)
    }

    /// Drop the cache explicitly when the keyboard leaves the lexicon feature.
    public static func releaseActiveLanguage() {
        lock.lock(); active = nil; lock.unlock()
    }

    private static func data(for language: KeyboardLanguage) -> DataSet {
        lock.lock(); defer { lock.unlock() }
        if let active, active.language == language { return active }
        let next = DataSet(language: language)
        active = next
        return next
    }
    private static func preparedData(for language: KeyboardLanguage) -> DataSet? {
        guard lock.try() else { return nil }
        defer { lock.unlock() }
        return active?.language == language ? active : nil
    }
    public static func isPrepared(language: KeyboardLanguage) -> Bool { preparedData(for: language) != nil }
    public static func words(language: KeyboardLanguage) -> [String] { data(for: language).words() }

    public static func completions(prefix: String, language: KeyboardLanguage, limit: Int = 3,
                                   cachedOnly: Bool = false, includeProfanity: Bool = false) -> [String] {
        let key = normalized(prefix)
        guard (1...24).contains(key.count), limit > 0,
              let dictionary = cachedOnly ? preparedData(for: language) : Optional(data(for: language)),
              let trie = dictionary.trie else { return [] }
        return dictionary.completions(prefix: key, limit: min(8, limit), includeProfanity: includeProfanity)
    }

    public struct SpellingCheck {
        public let known: Bool
        public let candidates: [String]
        public let rankedCandidates: [AutocorrectionEngine.Candidate]
    }

    public static func preparedCheck(_ word: String, language: KeyboardLanguage,
                                     includeProfanity: Bool = false) -> SpellingCheck? {
        guard let dictionary = preparedData(for: language), let trie = dictionary.trie else { return nil }
        let key = normalized(word)
        let known = trie.contains(key) || SupplementalVocabulary.words(for: language).contains { normalized($0) == key }
        let words = known ? [] : candidates(for: key, language: language, dictionary: dictionary, limit: 16)
            .filter { includeProfanity || !SupplementalVocabulary.isProfanity($0, language: language) }
        let rankings = dictionary.ranks(for: words)
        return SpellingCheck(known: known, candidates: words,
                             rankedCandidates: words.map { .init($0, frequencyRank: rankings[normalized($0)]) })
    }

    public static func contains(_ word: String, language: KeyboardLanguage) -> Bool {
        let dictionary = data(for: language)
        let key = normalized(word)
        return dictionary.trie?.contains(key) == true ||
            SupplementalVocabulary.words(for: language).contains { normalized($0) == key }
    }

    public static func frequencyIndex(word: String, language: KeyboardLanguage) -> Int? {
        frequencyIndices(words: [word], language: language)[normalized(word)]
    }
    public static func frequencyIndices(words: [String], language: KeyboardLanguage) -> [String: Int] {
        data(for: language).ranks(for: words)
    }

    public static func correctionCandidates(_ word: String, language: KeyboardLanguage, limit: Int = 8,
                                             includeProfanity: Bool = false) -> [String] {
        correctionCandidates(for: word, language: language, limit: limit, includeProfanity: includeProfanity)
    }
    public static func correctionCandidates(for word: String, language: KeyboardLanguage, limit: Int = 8,
                                             includeProfanity: Bool = false) -> [String] {
        let dictionary = data(for: language)
        return candidates(for: normalized(word), language: language, dictionary: dictionary, limit: limit)
            .filter { includeProfanity || !SupplementalVocabulary.isProfanity($0, language: language) }
    }

    private static func candidates(for word: String, language: KeyboardLanguage, dictionary: DataSet, limit: Int) -> [String] {
        guard (2...24).contains(word.count), limit > 0,
              dictionary.trie?.contains(word) == false else { return [] }
        let letters: [Character]
        switch language {
        case .english: letters = Array("abcdefghijklmnopqrstuvwxyz'-")
        case .russian: letters = Array("абвгдеёжзийклмнопрстуфхцчшщъыьэюя'-")
        case .ukrainian: letters = Array("абвгґдеєжзиіїйклмнопрстуфхцчшщьюя'-")
        }
        let source = Array(word)
        guard source.allSatisfy({ letters.contains($0) }) else { return [] }
        var found = Set<String>()
        func consider(_ characters: [Character]) {
            let candidate = String(characters)
            guard candidate != word else { return }
            if dictionary.trie?.contains(candidate) == true ||
                SupplementalVocabulary.words(for: language).contains(where: { normalized($0) == normalized(candidate) }) {
                found.insert(candidate)
            }
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
        let values = Array(found)
        let ranks = dictionary.ranks(for: values)
        return Array(values.sorted {
            let left = ranks[normalized($0)] ?? Int.max, right = ranks[normalized($1)] ?? Int.max
            return left == right ? $0 < $1 : left < right
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

private extension Data {
    var splitLinesCount: Int {
        withUnsafeBytes { raw in
            guard let bytes = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            var lines = 0
            for index in 0..<raw.count where bytes[index] == 10 { lines += 1 }
            return lines + (raw.count > 0 && bytes[raw.count - 1] != 10 ? 1 : 0)
        }
    }
}
