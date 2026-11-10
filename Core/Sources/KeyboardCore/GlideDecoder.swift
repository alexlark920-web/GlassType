import Foundation
import CoreGraphics

/// Offline geometric word decoder. A compact endpoint index covers the complete
/// bundled lexicon; only the best coarse matches reach the more expensive DTW.
public struct GlideDecoder {
    public init() {}

    /// Selects the mapped dictionary without materializing the glide index.
    /// The large geometric index is built only when a glide is actually decoded.
    public static func prepare(language: KeyboardLanguage) {
        storage.release()
        OfflineLexicon.activate(language: language)
    }

    public func decode(points: [CGPoint], keyCenters: [String: CGPoint],
                       language: KeyboardLanguage, extraWords: [String] = [], limit: Int = 3) -> [String] {
        decode(points: points, keyCenters: keyCenters, language: language, extraWords: extraWords, limit: limit, isCancelled: { false })
    }

    /// Cancellation-aware entry point used by the asynchronous glide actor.
    /// Checks are made while building/traversing the lexicon index and ranking candidates.
    public func decode(points: [CGPoint], keyCenters: [String: CGPoint], language: KeyboardLanguage,
                       extraWords: [String] = [], limit: Int = 3,
                       isCancelled: @Sendable () -> Bool) -> [String] {
        guard !isCancelled() else { return [] }
        guard limit > 0, (2...4096).contains(points.count), let geometry = Geometry(keyCenters) else { return [] }
        guard let index = Self.storage.index(for: language, isCancelled: isCancelled) else { return [] }
        let mapped = index.keyNames.map { keyCenters[$0].map(geometry.normalize) }
        var raw: [Point] = []
        let sampleCount = min(points.count, 256)
        for i in 0..<sampleCount {
            let source = points[i * (points.count - 1) / (sampleCount - 1)]
            guard source.x.isFinite, source.y.isFinite else { return [] }
            let p = geometry.normalize(source)
            guard geometry.contains(p) else { return [] }
            if let previous = raw.last, previous.distance(to: p) < 0.055 { continue }
            raw.append(p)
        }
        // Distance filtering removes dwell jitter without rounding away the
        // corners that distinguish words. Keep both contact endpoints exactly.
        if let end = points.last.map(geometry.normalize), let previous = raw.last, previous.distance(to: end) > 0.001 { raw.append(end) }
        raw = simplify(raw, tolerance: 0.065)
        guard raw.count >= 2, let first = raw.first, let last = raw.last else { return [] }
        let observedLength = pathLength(raw)
        guard observedLength >= 0.55, observedLength <= 110 else { return [] }
        let observed = resample(raw, count: 28)
        let coarseObserved = resample(raw, count: 12)
        let starts = nearestKeys(to: first, mapped: mapped)
        let ends = nearestKeys(to: last, mapped: mapped)
        guard !starts.isEmpty, !ends.isEmpty else { return [] }

        var candidateIndices = Set<Int>()
        for start in starts {
            for end in ends {
                if isCancelled() { return [] }
                let bucket = Index.bucket(start, end)
                if let entries = index.endpoints[bucket] { candidateIndices.formUnion(entries) }
            }
        }
        var candidates = candidateIndices.map { index.entries[$0] }
        var personal = Set<String>()
        for word in extraWords.prefix(200) {
            if isCancelled() { return [] }
            if let entry = index.entry(word, rank: 0), personal.insert(entry.word).inserted {
                candidates.append(entry)
            }
        }
        guard !candidates.isEmpty else { return [] }
        var seen = Set<String>()
        var shortlist: [Scored] = []
        for entry in candidates {
            if isCancelled() { return [] }
            guard seen.insert(entry.word).inserted else { continue }
            var template: [Point] = []
            var supported = true
            for key in entry.keys {
                guard let point = mapped[Int(key)] else { supported = false; break }
                template.append(point)
            }
            guard supported, template.count >= 2, let templateFirst = template.first, let templateLast = template.last else { continue }
            let startError = first.distance(to: templateFirst), endError = last.distance(to: templateLast)
            guard startError <= 1.65, endError <= 1.65 else { continue }
            let length = pathLength(template)
            guard length > 0 else { continue }
            let ratio = observedLength / length
            guard ratio >= 0.30, ratio <= 2.8 else { continue }
            let coarse = resample(template, count: 12)
            let direct = meanDistance(coarseObserved, coarse)
            guard direct <= 2.3 else { continue }
            let coverage = keyCoverage(template, trace: coarseObserved)
            let prior = personal.contains(entry.word) ? -0.055 : log(Double(entry.rank) + 2) / log(Double(index.entries.count) + 2) * 0.16
            let endpointPenalty = (startError + endError) * 0.18
            let lengthPenalty = abs(log(ratio)) * 0.11
            let preliminary = direct * 0.62 + coverage * 0.20 + endpointPenalty + lengthPenalty + prior
            shortlist.append(Scored(word: entry.word, template: template, coarse: preliminary,
                                    penalty: endpointPenalty + lengthPenalty + prior, coverage: coverage))
        }
        shortlist.sort { $0.coarse == $1.coarse ? $0.word < $1.word : $0.coarse < $1.coarse }
        var ranked: [(word: String, score: Double)] = []
        for item in shortlist.prefix(128) {
            if isCancelled() { return [] }
            let ideal = resample(item.template, count: observed.count)
            let direct = meanDistance(observed, ideal)
            let warped = alignmentCost(observed, ideal)
            let shape = warped * 0.68 + direct * 0.22 + item.coverage * 0.10
            let score = shape + item.penalty
            if shape <= 1.05, score <= 1.55 { ranked.append((item.word, score)) }
        }
        ranked.sort { $0.score == $1.score ? $0.word < $1.word : $0.score < $1.score }
        guard let best = ranked.first else { return [] }
        return ranked.filter { $0.score <= best.score + 0.42 }.prefix(min(limit, 3)).map(\.word)
    }

    private struct Point {
        let x: Double, y: Double
        func distance(to other: Point) -> Double {
            let dx = x - other.x, dy = y - other.y
            return (dx * dx + dy * dy).squareRoot()
        }
    }
    private struct Scored {
        let word: String
        let template: [Point]
        let coarse: Double
        let penalty: Double
        let coverage: Double
    }
    private struct Geometry {
        let pitchX: Double, pitchY: Double
        let minX: Double, maxX: Double, minY: Double, maxY: Double
        init?(_ centers: [String: CGPoint]) {
            let points = centers.values.filter { $0.x.isFinite && $0.y.isFinite }
            guard (5...64).contains(points.count) else { return nil }
            let rows = Array(Set(points.map { (Double($0.y) * 0.5).rounded() * 2 })).sorted()
            var horizontal: [Double] = []
            for row in rows {
                let xs = points.filter { abs(Double($0.y) - row) <= 2 }.map { Double($0.x) }.sorted()
                for pair in zip(xs, xs.dropFirst()) where pair.1 - pair.0 > 3 { horizontal.append(pair.1 - pair.0) }
            }
            horizontal.sort()
            guard !horizontal.isEmpty else { return nil }
            pitchX = horizontal[horizontal.count / 2]
            let vertical = zip(rows, rows.dropFirst()).map { $0.1 - $0.0 }.filter { $0 > 3 }.sorted()
            pitchY = vertical.isEmpty ? pitchX : vertical[vertical.count / 2]
            guard pitchX >= 3, pitchY >= 3,
                  let lowX = points.map({ Double($0.x) }).min(), let highX = points.map({ Double($0.x) }).max(),
                  let lowY = points.map({ Double($0.y) }).min(), let highY = points.map({ Double($0.y) }).max() else { return nil }
            minX = lowX / pitchX; maxX = highX / pitchX; minY = lowY / pitchY; maxY = highY / pitchY
        }
        func normalize(_ point: CGPoint) -> Point { Point(x: Double(point.x) / pitchX, y: Double(point.y) / pitchY) }
        func contains(_ point: Point) -> Bool {
            point.x >= minX - 1.8 && point.x <= maxX + 1.8 && point.y >= minY - 1.8 && point.y <= maxY + 1.8
        }
    }
    private struct Entry {
        let word: String
        let keys: [UInt8]
        let rank: Int
    }
    private struct Index {
        let language: KeyboardLanguage
        let keyNames: [String]
        let ids: [String: UInt8]
        var entries: [Entry] = []
        var endpoints: [UInt16: [Int]] = [:]
        init?(language: KeyboardLanguage, isCancelled: @Sendable () -> Bool) {
            self.language = language
            keyNames = language.rows.flatMap { $0 }
            ids = Dictionary(uniqueKeysWithValues: keyNames.enumerated().map { ($0.element, UInt8($0.offset)) })
            var seen = Set<String>()
            guard let words = GlideDecoder.words(for: language, isCancelled: isCancelled) else { return nil }
            for (rank, word) in words.enumerated() {
                if rank.isMultiple(of: 128), isCancelled() { return nil }
                guard let candidate = entry(word, rank: rank), seen.insert(candidate.word).inserted,
                      let first = candidate.keys.first, let last = candidate.keys.last else { continue }
                endpoints[Self.bucket(Int(first), Int(last)), default: []].append(entries.count)
                entries.append(candidate)
            }
        }
        func entry(_ source: String, rank: Int) -> Entry? {
            guard (2...24).contains(source.count), source.first?.isLetter == true, source.last?.isLetter == true,
                  source.allSatisfy({ $0.isLetter || "'’ʼ-".contains($0) }) else { return nil }
            let word = source.lowercased()
            var keys: [UInt8] = []
            for character in word {
                if !character.isLetter { continue }
                var key = String(character)
                if language == .russian && key == "ё" { key = "е" }
                if language == .russian && key == "ъ" { key = "ь" }
                if language == .ukrainian && key == "ґ" { key = "г" }
                if language == .ukrainian && key == "ї" { key = "і" }
                if language == .english { key = key.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en")) }
                guard let id = ids[key] else { return nil }
                if keys.last != id { keys.append(id) }
            }
            guard keys.count >= 2 else { return nil }
            return Entry(word: word, keys: keys, rank: rank)
        }
        static func bucket(_ first: Int, _ last: Int) -> UInt16 { UInt16(first << 8 | last) }
    }
    /// Only the active language's endpoint index is kept, bounding extension RAM.
    private final class IndexStorage: @unchecked Sendable {
        private let lock = NSLock()
        private var cached: Index?
        func index(for language: KeyboardLanguage, isCancelled: @Sendable () -> Bool) -> Index? {
            lock.lock(); defer { lock.unlock() }
            if let cached, cached.language == language { return isCancelled() ? nil : cached }
            guard let index = Index(language: language, isCancelled: isCancelled) else { return nil }
            cached = index; return index
        }
        func release() {
            lock.lock(); cached = nil; lock.unlock()
        }
    }
    private static let storage = IndexStorage()

    private func nearestKeys(to point: Point, mapped: [Point?]) -> [Int] {
        mapped.enumerated().compactMap { index, candidate -> (Int, Double)? in
            guard let candidate else { return nil }
            let distance = point.distance(to: candidate)
            return distance <= 1.65 ? (index, distance) : nil
        }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }.prefix(5).map(\.0)
    }
    private func pathLength(_ points: [Point]) -> Double {
        guard points.count > 1 else { return 0 }
        return zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }
    private func meanDistance(_ a: [Point], _ b: [Point]) -> Double {
        zip(a, b).reduce(0) { $0 + $1.0.distance(to: $1.1) } / Double(max(1, min(a.count, b.count)))
    }
    private func resample(_ points: [Point], count: Int) -> [Point] {
        let total = pathLength(points)
        guard total > 0, let first = points.first, let last = points.last else { return [] }
        var result = [first], segment = 1
        var consumed = 0.0
        for sample in 1..<(count - 1) {
            let target = total * Double(sample) / Double(count - 1)
            while segment < points.count - 1 && consumed + points[segment - 1].distance(to: points[segment]) < target {
                consumed += points[segment - 1].distance(to: points[segment]); segment += 1
            }
            let start = points[segment - 1], end = points[segment]
            let segmentLength = start.distance(to: end)
            let f = segmentLength > 0 ? min(1, max(0, (target - consumed) / segmentLength)) : 0
            result.append(Point(x: start.x + (end.x - start.x) * f, y: start.y + (end.y - start.y) * f))
        }
        result.append(last); return result
    }
    private func keyCoverage(_ keys: [Point], trace: [Point]) -> Double {
        keys.reduce(0) { total, key in
            var minimum = 10.0
            for (start, end) in zip(trace, trace.dropFirst()) {
                let dx = end.x - start.x, dy = end.y - start.y
                let squared = dx * dx + dy * dy
                let t = squared > 0 ? min(1, max(0, ((key.x - start.x) * dx + (key.y - start.y) * dy) / squared)) : 0
                minimum = min(minimum, key.distance(to: Point(x: start.x + t * dx, y: start.y + t * dy)))
            }
            return total + minimum
        } / Double(max(1, keys.count))
    }
    private func alignmentCost(_ observed: [Point], _ ideal: [Point]) -> Double {
        let count = observed.count
        guard count > 0, ideal.count == count else { return .infinity }
        var previous = Array(repeating: Double.infinity, count: count + 1)
        var current = previous
        previous[0] = 0
        for i in 1...count {
            for column in current.indices { current[column] = .infinity }
            for j in max(1, i - 9)...min(count, i + 9) {
                let d = observed[i - 1].distance(to: ideal[j - 1])
                current[j] = d * d + min(previous[j - 1], min(previous[j], current[j - 1]))
            }
            swap(&previous, &current)
        }
        return (previous[count] / Double(count * 2)).squareRoot()
    }

    private func simplify(_ points: [Point], tolerance: Double) -> [Point] {
        guard points.count > 3 else { return points }
        var keep = Array(repeating: false, count: points.count)
        keep[0] = true; keep[points.count - 1] = true
        var segments = [(0, points.count - 1)]
        while let (start, end) = segments.popLast() {
            guard end > start + 1 else { continue }
            let a = points[start], b = points[end]
            let dx = b.x - a.x, dy = b.y - a.y, squared = dx * dx + dy * dy
            var maximum = tolerance, selected: Int?
            for index in (start + 1)..<end {
                let p = points[index]
                let t = squared > 0 ? min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / squared)) : 0
                let distance = p.distance(to: Point(x: a.x + t * dx, y: a.y + t * dy))
                if distance > maximum { maximum = distance; selected = index }
            }
            if let selected { keep[selected] = true; segments.append((start, selected)); segments.append((selected, end)) }
        }
        return points.indices.compactMap { keep[$0] ? points[$0] : nil }
    }
}
