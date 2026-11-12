import Foundation

/// Memory-mapped local dictionaries. Only the selected language is retained;
/// word strings are materialized only for the glide decoder compatibility API.
public enum OfflineLexicon {
    private final class DataSet: @unchecked Sendable {
        private struct RankEntry {
            let hash: UInt64
            let rank: Int
            let offset: Int
            let length: Int
        }

        let language: KeyboardLanguage
        let trie: MappedBinaryLexicon?
        let orderedWords: StableMappedBytes?
        private let rankLock = NSLock()
        private var rankCache: [String: Int] = [:]
        private let rankIndexLock = NSLock()
        private var rankIndex: [RankEntry]?
        private var cachedLineCount: Int?

        init(language: KeyboardLanguage) {
            self.language = language
            let name = "lexicon_" + language.rawValue
            if let url = Bundle.module.url(forResource: name, withExtension: "trie") {
                trie = try? MappedBinaryLexicon(url: url)
            } else {
                trie = nil
            }
            if let url = Bundle.module.url(forResource: name, withExtension: "txt") {
                orderedWords = try? StableMappedBytes(url: url)
            } else {
                orderedWords = nil
            }
        }

        func words() -> [String] {
            words(isCancelled: { false }) ?? []
        }

        func words(isCancelled: @Sendable () -> Bool) -> [String]? {
            var bundled: [String] = []
            if let orderedWords {
                guard let parsed = Self.collectWords(in: orderedWords, limit: 51_000, isCancelled: isCancelled) else { return nil }
                bundled = parsed
            }
            var result = bundled
            var seen = Set(bundled)
            for (index, word) in SupplementalVocabulary.words(for: language).enumerated() {
                if index.isMultiple(of: 128), isCancelled() { return nil }
                if seen.insert(word).inserted { result.append(word) }
            }
            return result
        }

        /// Build a compact hash-to-source-offset index once. Ranking then does a
        /// logarithmic lookup instead of rescanning the entire mapped dictionary
        /// for every streaming frame. Offsets let us verify hash collisions without
        /// storing every word as a separate String.
        private func preparedRankIndex() -> [RankEntry]? {
            guard let orderedWords else { return nil }
            rankIndexLock.lock()
            defer { rankIndexLock.unlock() }
            if let rankIndex { return rankIndex }

            let bytes = orderedWords.base
            let rawCount = orderedWords.count
            var result: [RankEntry] = []
            result.reserveCapacity(80_000)
            var start = 0
            var rank = 0
            for end in 0...rawCount {
                guard end == rawCount || bytes[end] == 10 else { continue }
                var wordEnd = end
                if wordEnd > start, bytes[wordEnd - 1] == 13 { wordEnd -= 1 }
                if let tab = (start..<wordEnd).first(where: { bytes[$0] == 9 }) { wordEnd = tab }
                if wordEnd > start {
                    let view = UnsafeBufferPointer(start: bytes + start, count: wordEnd - start)
                    result.append(RankEntry(hash: Self.hash(view), rank: rank, offset: start, length: wordEnd - start))
                    rank += 1
                }
                start = end + 1
            }
            result.sort { $0.hash < $1.hash }
            var newlines = 0
            for index in 0..<rawCount where bytes[index] == 10 { newlines += 1 }
            if rawCount > 0, bytes[rawCount - 1] != 10 { newlines += 1 }
            cachedLineCount = newlines
            rankIndex = result
            return result
        }

        func warmRankIndex() {
            _ = preparedRankIndex()
        }

        /// Rank one UTF-8 word against the mapped dictionary. Does not copy the
        /// query or the mapped bytes into a `String`, `Array`, or `Dictionary`.
        func rank(utf8 query: UnsafeBufferPointer<UInt8>) -> Int? {
            guard !query.isEmpty, let index = preparedRankIndex() else { return nil }
            let hash = Self.hash(query)
            var low = 0
            var high = index.count
            while low < high {
                let mid = low + (high - low) / 2
                if index[mid].hash < hash { low = mid + 1 } else { high = mid }
            }
            if let orderedWords {
                let source = orderedWords.base
                var cursor = low
                while cursor < index.count, index[cursor].hash == hash {
                    let entry = index[cursor]
                    if entry.length == query.count,
                       UnsafeBufferPointer(start: source + entry.offset, count: entry.length).elementsEqual(query) {
                        return entry.rank
                    }
                    cursor += 1
                }
            }
            let base = cachedLineCount ?? 0
            for (offset, word) in SupplementalVocabulary.words(for: language).enumerated() {
                var index = 0
                var matches = true
                for byte in word.utf8 {
                    if index >= query.count || query[index] != byte { matches = false; break }
                    index += 1
                }
                if matches, index == query.count { return base + offset }
            }
            return nil
        }

        /// Rank the small candidate set. The one-time index is shared across calls;
        /// the cache avoids even binary searches for recently seen beam candidates.
        func ranks(for words: [String]) -> [String: Int] {
            guard let orderedWords, !words.isEmpty,
                  let index = preparedRankIndex() else { return [:] }

            let normalizedWords = words.map(OfflineLexicon.normalized)
            rankLock.lock()
            var result: [String: Int] = [:]
            for word in normalizedWords {
                if let rank = rankCache[word] { result[word] = rank }
            }
            rankLock.unlock()

            let missing = Set(normalizedWords.filter { result[$0] == nil })
            if !missing.isEmpty {
                let source = orderedWords.base
                for word in missing {
                    var searched = false
                    word.utf8.withContiguousStorageIfAvailable { query in
                        searched = true
                        let hash = Self.hash(query)
                        var low = 0
                        var high = index.count
                        while low < high {
                            let mid = low + (high - low) / 2
                            if index[mid].hash < hash { low = mid + 1 } else { high = mid }
                        }
                        var cursor = low
                        while cursor < index.count, index[cursor].hash == hash {
                            let entry = index[cursor]
                            if entry.length == query.count,
                               UnsafeBufferPointer(start: source + entry.offset, count: entry.length).elementsEqual(query) {
                                result[word] = entry.rank
                                break
                            }
                            cursor += 1
                        }
                    }
                    if searched { continue }
                    let query = Array(word.utf8)
                    let hash = query.withUnsafeBufferPointer { Self.hash($0) }
                    var low = 0
                    var high = index.count
                    while low < high {
                        let mid = low + (high - low) / 2
                        if index[mid].hash < hash { low = mid + 1 } else { high = mid }
                    }
                    var cursor = low
                    while cursor < index.count, index[cursor].hash == hash {
                        let entry = index[cursor]
                        if entry.length == query.count,
                           query.withUnsafeBufferPointer({ queryBuffer in
                               UnsafeBufferPointer(start: source + entry.offset, count: entry.length).elementsEqual(queryBuffer)
                           }) {
                            result[word] = entry.rank
                            break
                        }
                        cursor += 1
                    }
                }
            }

            let extras = SupplementalVocabulary.words(for: language)
            let baseRank = cachedLineCount ?? Self.lineCount(orderedWords)
            for (offset, word) in extras.enumerated() {
                let key = OfflineLexicon.normalized(word)
                if result[key] == nil { result[key] = baseRank + offset }
            }

            rankLock.lock()
            if rankCache.count + result.count > 1_024 { rankCache.removeAll(keepingCapacity: true) }
            rankCache.merge(result) { old, _ in old }
            rankLock.unlock()
            return result
        }

        func completions(prefix: String, limit: Int, includeProfanity: Bool) -> [String] {
            guard limit > 0, let trie else { return [] }
            let key = OfflineLexicon.normalized(prefix)
            var result: [String] = []
            if key.count >= 3 {
                result = SupplementalVocabulary.words(for: language).filter {
                    OfflineLexicon.normalized($0).hasPrefix(key) && OfflineLexicon.normalized($0) != key &&
                        (includeProfanity || !SupplementalVocabulary.isProfanity($0, language: language))
                }
                if result.count >= limit { return Array(result.prefix(limit)) }
            }
            guard trie.findWords(matchingPrefix: key, limit: 1).isEmpty == false else { return result }
            guard let orderedWords else {
                let mapped = trie.findWords(matchingPrefix: key, limit: limit + 1)
                return (result + mapped.filter { OfflineLexicon.normalized($0) != key }).prefix(limit).map { $0 }
            }
            let bytes = orderedWords.base
            let rawCount = orderedWords.count
            var foundRanks: [String: Int] = [:]
            let prefixCount = key.utf8.count
            withUnsafeTemporaryAllocation(of: UInt8.self, capacity: max(1, prefixCount)) { prefixStorage in
                guard let prefixBase = prefixStorage.baseAddress else { return }
                var prefixLength = 0
                for byte in key.utf8 {
                    prefixBase[prefixLength] = byte
                    prefixLength += 1
                }
                let prefixBytes = UnsafeBufferPointer(start: prefixBase, count: prefixLength)
                var start = 0
                var rank = 0
                for end in 0...rawCount {
                    guard end == rawCount || bytes[end] == 10 else { continue }
                    var wordEnd = end
                    if wordEnd > start, bytes[wordEnd - 1] == 13 { wordEnd -= 1 }
                    if let tab = (start..<wordEnd).first(where: { bytes[$0] == 9 }) { wordEnd = tab }
                    if wordEnd - start >= prefixBytes.count,
                       UnsafeBufferPointer(start: bytes + start, count: prefixBytes.count).starts(with: prefixBytes) {
                        let word = String(decoding: UnsafeBufferPointer(start: bytes + start, count: wordEnd - start), as: UTF8.self)
                        if OfflineLexicon.normalized(word) != key,
                           (includeProfanity || !SupplementalVocabulary.isProfanity(word, language: language)),
                           !result.contains(where: { OfflineLexicon.normalized($0) == OfflineLexicon.normalized(word) }),
                           trie.contains(word) {
                            result.append(word)
                            foundRanks[OfflineLexicon.normalized(word)] = rank
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

        private static func collectWords(in mapped: StableMappedBytes, limit: Int, isCancelled: @Sendable () -> Bool) -> [String]? {
            let bytes = mapped.base
            var result: [String] = []
            var start = 0
            var line = 0
            for end in 0...mapped.count {
                guard end == mapped.count || bytes[end] == 10 else { continue }
                if line.isMultiple(of: 128), isCancelled() { return nil }
                var wordEnd = end
                if wordEnd > start, bytes[wordEnd - 1] == 13 { wordEnd -= 1 }
                if let tab = (start..<wordEnd).first(where: { bytes[$0] == 9 }) { wordEnd = tab }
                if wordEnd > start, result.count < limit {
                    result.append(String(decoding: UnsafeBufferPointer(start: bytes + start, count: wordEnd - start), as: UTF8.self))
                }
                start = end + 1
                line += 1
            }
            return result
        }

        private static func lineCount(_ mapped: StableMappedBytes) -> Int {
            let bytes = mapped.base
            var lines = 0
            for index in 0..<mapped.count where bytes[index] == 10 { lines += 1 }
            return lines + (mapped.count > 0 && bytes[mapped.count - 1] != 10 ? 1 : 0)
        }

        private static func hash(_ bytes: [UInt8]) -> UInt64 {
            bytes.withUnsafeBufferPointer { hash($0) }
        }
        private static func hash(_ bytes: UnsafeBufferPointer<UInt8>) -> UInt64 {
            bytes.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        }
    }

    /// Owns the mutable active snapshot behind one lock-protected Sendable reference.
    private final class ActiveDataSetStorage: @unchecked Sendable {
        private let lock = NSLock()
        private var active: DataSet?

        func activate(language: KeyboardLanguage) {
            lock.lock(); defer { lock.unlock() }
            guard active?.language != language else { return }
            active = DataSet(language: language)
        }

        func release() {
            lock.lock(); active = nil; lock.unlock()
        }

        func data(for language: KeyboardLanguage) -> DataSet {
            lock.lock(); defer { lock.unlock() }
            if let active, active.language == language { return active }
            let next = DataSet(language: language)
            active = next
            return next
        }

        func preparedData(for language: KeyboardLanguage) -> DataSet? {
            guard lock.try() else { return nil }
            defer { lock.unlock() }
            return active?.language == language ? active : nil
        }
    }

    public static var licenseNotice: String {
        ["Dictionary-Attribution", "CC-BY-SA-4.0", "MPL-1.1"].compactMap { name in
            Bundle.module.url(forResource: name, withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        }.joined(separator: "\n\n")
    }

    private static let activeDataSet = ActiveDataSetStorage()

    /// Select a language and release the previous mapped resource immediately
    /// when no in-flight caller still holds it.
    public static func activate(language: KeyboardLanguage) {
        activeDataSet.activate(language: language)
    }

    /// Drop the cache explicitly when the keyboard leaves the lexicon feature.
    public static func releaseActiveLanguage() {
        activeDataSet.release()
    }

    private static func data(for language: KeyboardLanguage) -> DataSet {
        activeDataSet.data(for: language)
    }
    private static func preparedData(for language: KeyboardLanguage) -> DataSet? {
        activeDataSet.preparedData(for: language)
    }
    public static func isPrepared(language: KeyboardLanguage) -> Bool { preparedData(for: language) != nil }
    public static func words(language: KeyboardLanguage) -> [String] { data(for: language).words() }
    static func words(language: KeyboardLanguage, isCancelled: @Sendable () -> Bool) -> [String]? {
        data(for: language).words(isCancelled: isCancelled)
    }

    public static func completions(prefix: String, language: KeyboardLanguage, limit: Int = 3,
                                   cachedOnly: Bool = false, includeProfanity: Bool = false) -> [String] {
        let key = normalized(prefix)
        guard (1...24).contains(key.count), limit > 0,
              let dictionary = cachedOnly ? preparedData(for: language) : Optional(data(for: language)),
              dictionary.trie != nil else { return [] }
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

    /// Builds the mapped rank index off the touch path so the first frame does not scan the file.
    static func prepareFrequencyIndex(language: KeyboardLanguage) {
        data(for: language).warmRankIndex()
    }

    /// Scalar rank for a beam word already held as UTF-8. No intermediate `String`.
    static func frequencyRank(utf8: UnsafeBufferPointer<UInt8>, language: KeyboardLanguage) -> Int? {
        data(for: language).rank(utf8: utf8)
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

    // Shared within KeyboardCore so the glide decoder can query normalized ranks.
    static func normalized(_ word: String) -> String {
        word.precomposedStringWithCanonicalMapping.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "ʼ", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "‑", with: "-")
    }
}
