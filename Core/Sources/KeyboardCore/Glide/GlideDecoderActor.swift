import CoreGraphics
import Foundation
import simd

/// A candidate produced by continuous streaming beam search.
public struct Candidate: Sendable, Equatable {
    public let word: String
    public let score: Float
    public let spatialScore: Float
    public let frequencyScore: Float
    public let isTerminal: Bool

    public init(word: String, score: Float, spatialScore: Float = 0, frequencyScore: Float = 0, isTerminal: Bool = true) {
        self.word = word
        self.score = score
        self.spatialScore = spatialScore
        self.frequencyScore = frequencyScore
        self.isTerminal = isTerminal
    }
}

/// Shared generation counter allowing a newly emitted touch to invalidate a frame
/// even while the decoder actor is synchronously traversing the mapped trie.
private final class GlideFrameEpoch: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0

    func advance() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        value &+= 1
        return value
    }

    func isCurrent(_ expected: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value == expected
    }

    func invalidate() {
        lock.lock()
        value &+= 1
        lock.unlock()
    }
}

/// Serializes glide decoding and continuous streaming beam search away from the UI executor.
/// Complies with Swift 6 strict concurrency, frame budgets (<=8ms for 120Hz), and cancellation.
public actor GlideDecoderActor {
    /// Fixed UTF-8 buffer. Beam expansion copies these bytes; it never builds a `String`.
    private struct InlineWord: Sendable {
        static let capacity = 48
        var count: UInt8 = 0
        var storage: (UInt64, UInt64, UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0, 0, 0)

        mutating func append(utf8: (UInt8, UInt8, UInt8, UInt8), length: UInt8) -> Bool {
            let n = Int(length)
            let start = Int(count)
            guard n > 0, n <= 4, start + n <= Self.capacity else { return false }
            var local = storage
            withUnsafeMutableBytes(of: &local) { raw in
                guard let dest = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                dest[start] = utf8.0
                if n > 1 { dest[start + 1] = utf8.1 }
                if n > 2 { dest[start + 2] = utf8.2 }
                if n > 3 { dest[start + 3] = utf8.3 }
            }
            storage = local
            count = UInt8(start + n)
            return true
        }

        mutating func append(byte: UInt8) -> Bool {
            let start = Int(count)
            guard start < Self.capacity else { return false }
            var local = storage
            withUnsafeMutableBytes(of: &local) { raw in
                raw[start] = byte
            }
            storage = local
            count = UInt8(start + 1)
            return true
        }

        func withBytes<T>(_ body: (UnsafeBufferPointer<UInt8>) -> T) -> T {
            var storage = self.storage
            let count = Int(self.count)
            return withUnsafeBytes(of: &storage) { raw in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return body(UnsafeBufferPointer(start: nil, count: 0))
                }
                return body(UnsafeBufferPointer(start: base, count: count))
            }
        }

        func makeString() -> String {
            withBytes { String(decoding: $0, as: UTF8.self) }
        }
    }

    private struct ExtraWord: Sendable {
        var hash: UInt64
        var word: InlineWord
    }

    private struct RankedPath: Sendable {
        var index: Int
        var score: Float
        var spatialScore: Float
        var frequencyScore: Float
        var isTerminal: Bool
    }

    private struct BeamPath: Sendable {
        var node: Int
        var word: InlineWord
        var cumulativeSpatialScore: Float
        var length: Int
        var lastKeyIndex: Int16
        var isTerminal: Bool
    }

    private let fallbackDecoder = GlideDecoder()
    private var spatialModel: SpatialTouchModel?
    private var lexicon: MappedBinaryLexicon?
    private var activeLanguage: KeyboardLanguage = .english
    private var activeBeam: [BeamPath] = []
    private var pendingBeam: [BeamPath] = []
    private var scoredScratch: [SpatialTouchModel.ScoredKey] = Array(repeating: .init(), count: 6)
    private var lastProcessedTimestamp: TimeInterval = 0
    private var lastProcessedPoint: CGPoint = .zero
    private let tuning: KeyboardTuningConfig
    private var frameInterval: TimeInterval
    private var beamWidth: Int
    private var wSpatial: Float
    private var wFreq: Float
    private var extraWords: [ExtraWord] = []
    private var rankedScratch: [RankedPath] = []

    public init(tuning: KeyboardTuningConfig = .current) {
        self.tuning = tuning
        self.frameInterval = tuning.frameThrottleInterval
        self.beamWidth = tuning.beamWidth
        self.wSpatial = tuning.spatialWeight
        self.wFreq = tuning.frequencyWeight
    }

    // MARK: - Configuration & Session Lifecycle

    /// Resets the active beam search paths and touch timestamps.
    public func resetBeam() {
        activeBeam.removeAll(keepingCapacity: true)
        pendingBeam.removeAll(keepingCapacity: true)
        lastProcessedTimestamp = 0
        lastProcessedPoint = .zero
    }

    /// Configures the streaming beam search session for an active layout and language.
    public func configure(
        keyCenters: [String: CGPoint],
        language: KeyboardLanguage,
        extraWords: [String] = [],
        beamWidth: Int? = nil,
        wSpatial: Float? = nil,
        wFreq: Float? = nil,
        frameInterval: TimeInterval? = nil
    ) throws {
        let mapped = try MappedBinaryLexicon(bundledLanguage: language)
        let model = SpatialTouchModel(keyCenters: keyCenters, tuning: tuning)
        let beamWidth = beamWidth ?? tuning.beamWidth
        let wSpatial = wSpatial ?? tuning.spatialWeight
        let wFreq = wFreq ?? tuning.frequencyWeight
        let frameInterval = frameInterval ?? tuning.frameThrottleInterval
        var extras: [ExtraWord] = []
        extras.reserveCapacity(extraWords.count)
        for raw in extraWords {
            let normalized = OfflineLexicon.normalized(raw)
            var word = InlineWord()
            var accepted = true
            for byte in normalized.utf8 {
                if !word.append(byte: byte) { accepted = false; break }
            }
            guard accepted, word.count > 0 else { continue }
            extras.append(ExtraWord(hash: word.withBytes(Self.fnv), word: word))
        }
        extras.sort { $0.hash < $1.hash }
        OfflineLexicon.activate(language: language)
        OfflineLexicon.prepareFrequencyIndex(language: language)
        self.activeLanguage = language
        self.beamWidth = max(4, min(64, beamWidth))
        self.wSpatial = wSpatial
        self.wFreq = wFreq
        self.frameInterval = max(0.001, frameInterval)
        self.extraWords = extras
        self.spatialModel = model
        self.lexicon = mapped
        let capacity = self.beamWidth * 8
        if activeBeam.capacity < capacity { activeBeam.reserveCapacity(capacity) }
        if pendingBeam.capacity < capacity { pendingBeam.reserveCapacity(capacity) }
        if rankedScratch.capacity < self.beamWidth { rankedScratch.reserveCapacity(self.beamWidth) }
        resetBeam()
    }

    // MARK: - Single Frame Processing

    /// Processes a touch frame on this background actor. Cancellation is checked during beam expansion.
    public func processTouchFrame(point: CGPoint, timestamp: TimeInterval) throws -> [Candidate] {
        try processTouchFrame(point: point, timestamp: timestamp, epoch: nil, expectedEpoch: 0)
    }

    private func processTouchFrame(
        point: CGPoint,
        timestamp: TimeInterval,
        epoch: GlideFrameEpoch?,
        expectedEpoch: UInt64
    ) throws -> [Candidate] {
        try Task.checkCancellation()
        #if DEBUG
        let measureFrame = tuning.diagnosticsEnabled
        var frameStarted: UInt64 = 0
        var frameSampled = false
        defer {
            if measureFrame, frameSampled {
                KeyboardFrameDiagnostics.shared.record(nanoseconds: DispatchTime.now().uptimeNanoseconds &- frameStarted)
            }
        }
        #endif
        guard epoch.map({ $0.isCurrent(expectedEpoch) }) ?? true else { throw CancellationError() }
        guard let spatial = spatialModel, let lex = lexicon else { return [] }

        // Enforce frame budget throttling (target interval <= 8ms for 120Hz).
        if lastProcessedTimestamp > 0, timestamp - lastProcessedTimestamp < frameInterval {
            let dx = point.x - lastProcessedPoint.x, dy = point.y - lastProcessedPoint.y
            if dx * dx + dy * dy < 16.0 {
                return try currentTopCandidates(limit: 5, epoch: epoch, expectedEpoch: expectedEpoch)
            }
        }
        lastProcessedTimestamp = timestamp
        lastProcessedPoint = point
        #if DEBUG
        if measureFrame {
            frameSampled = true
            frameStarted = DispatchTime.now().uptimeNanoseconds
        }
        #endif

        let touchSIMD = SIMD2<Float>(Float(point.x), Float(point.y))
        let candidateCount = scoredScratch.withUnsafeMutableBufferPointer { buf in
            spatial.evaluate(touch: touchSIMD, into: buf, probabilityThreshold: 0.001)
        }
        guard candidateCount > 0 else { return try currentTopCandidates(limit: 5, epoch: epoch, expectedEpoch: expectedEpoch) }

        try checkFrame(epoch, expectedEpoch)
        pendingBeam.removeAll(keepingCapacity: true)

        if activeBeam.isEmpty {
            // First touch: spawn initial beam paths from Trie root.
            let root = lex.rootNode()
            for i in 0..<candidateCount {
                try checkFrame(epoch, expectedEpoch)
                let idx = Int(scoredScratch[i].keyIndex)
                guard spatial.encodings.indices.contains(idx) else { continue }
                let encoding = spatial.encodings[idx]
                if let transition = try lex.transition(from: root, utf8: encoding.bytes, length: encoding.length) {
                    var word = InlineWord()
                    guard word.append(utf8: encoding.bytes, length: encoding.length) else { continue }
                    pendingBeam.append(BeamPath(
                        node: transition.node,
                        word: word,
                        cumulativeSpatialScore: scoredScratch[i].logProbability,
                        length: 1,
                        lastKeyIndex: Int16(idx),
                        isTerminal: transition.isTerminal
                    ))
                }
            }
        } else {
            // Successive touch: retain a dwell path and also try a trie transition.
            // The transition must be allowed even when the key is unchanged, since
            // repeated letters (for example the two l's in "hello") are distinct strokes.
            for path in activeBeam {
                try checkFrame(epoch, expectedEpoch)

                // Dwell on current key (finger dwelling/hovering over the same key).
                for i in 0..<candidateCount {
                    try checkFrame(epoch, expectedEpoch)
                    let idx = Int(scoredScratch[i].keyIndex)
                    if idx == Int(path.lastKeyIndex), spatial.encodings.indices.contains(idx) {
                        pendingBeam.append(BeamPath(
                            node: path.node,
                            word: path.word,
                            cumulativeSpatialScore: path.cumulativeSpatialScore + scoredScratch[i].logProbability * 0.5,
                            length: path.length,
                            lastKeyIndex: path.lastKeyIndex,
                            isTerminal: path.isTerminal
                        ))
                        break
                    }
                }

                // Transition to a new trie character. This intentionally includes the
                // same key: consecutive same-letter strokes must advance the trie.
                for i in 0..<candidateCount {
                    try checkFrame(epoch, expectedEpoch)
                    let idx = Int(scoredScratch[i].keyIndex)
                    guard spatial.encodings.indices.contains(idx) else { continue }
                    let encoding = spatial.encodings[idx]
                    if let transition = try lex.transition(from: path.node, utf8: encoding.bytes, length: encoding.length) {
                        var word = path.word
                        guard word.append(utf8: encoding.bytes, length: encoding.length) else { continue }
                        pendingBeam.append(BeamPath(
                            node: transition.node,
                            word: word,
                            cumulativeSpatialScore: path.cumulativeSpatialScore + scoredScratch[i].logProbability,
                            length: path.length + 1,
                            lastKeyIndex: Int16(idx),
                            isTerminal: transition.isTerminal
                        ))
                    }
                }
            }
        }

        try checkFrame(epoch, expectedEpoch)
        // Prune to Top-K using normalized spatial scores.
        pendingBeam.sort {
            let leftNorm = $0.cumulativeSpatialScore / Float(max(1, $0.length))
            let rightNorm = $1.cumulativeSpatialScore / Float(max(1, $1.length))
            return leftNorm > rightNorm
        }
        if pendingBeam.count > beamWidth {
            pendingBeam.removeSubrange(beamWidth..<pendingBeam.count)
        }
        try checkFrame(epoch, expectedEpoch)
        swap(&activeBeam, &pendingBeam)
        do {
            return try currentTopCandidates(limit: 5, epoch: epoch, expectedEpoch: expectedEpoch)
        } catch {
            // The failed frame must not stay in the beam a newer touch extends.
            swap(&activeBeam, &pendingBeam)
            pendingBeam.removeAll(keepingCapacity: true)
            throw error
        }
    }

    private func checkFrame(_ epoch: GlideFrameEpoch?, _ expectedEpoch: UInt64) throws {
        try Task.checkCancellation()
        guard epoch.map({ $0.isCurrent(expectedEpoch) }) ?? true else { throw CancellationError() }
    }

    /// Computes fused scores for the current beam and returns top candidates.
    /// Strings are materialized only for the already-pruned beam, never during trie expansion.
    private func currentTopCandidates(limit: Int, epoch: GlideFrameEpoch?, expectedEpoch: UInt64) throws -> [Candidate] {
        guard !activeBeam.isEmpty else { return [] }
        rankedScratch.removeAll(keepingCapacity: true)

        for index in activeBeam.indices {
            try checkFrame(epoch, expectedEpoch)
            let path = activeBeam[index]
            let normSpatial = path.cumulativeSpatialScore / Float(max(1, path.length))
            let rank = path.word.withBytes { bytes -> Int in
                if self.containsExtra(bytes) { return 0 }
                return OfflineLexicon.frequencyRank(utf8: bytes, language: self.activeLanguage) ?? 50_000
            }
            let logFreq = -log(Float(rank + 10))
            let finalScore = (wSpatial * normSpatial) + (wFreq * logFreq)
            rankedScratch.append(RankedPath(
                index: index,
                score: finalScore,
                spatialScore: normSpatial,
                frequencyScore: logFreq,
                isTerminal: path.isTerminal
            ))
        }

        rankedScratch.sort {
            if $0.isTerminal != $1.isTerminal { return $0.isTerminal && !$1.isTerminal }
            return $0.score > $1.score
        }
        let kept = min(rankedScratch.count, max(1, limit))
        var scored: [Candidate] = []
        scored.reserveCapacity(kept)
        for offset in 0..<kept {
            try checkFrame(epoch, expectedEpoch)
            let item = rankedScratch[offset]
            scored.append(Candidate(
                word: activeBeam[item.index].word.makeString(),
                score: item.score,
                spatialScore: item.spatialScore,
                frequencyScore: item.frequencyScore,
                isTerminal: item.isTerminal
            ))
        }
        return scored
    }

    private func containsExtra(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        guard !bytes.isEmpty, !extraWords.isEmpty else { return false }
        let hash = Self.fnv(bytes)
        var low = 0
        var high = extraWords.count
        while low < high {
            let mid = low + (high - low) / 2
            if extraWords[mid].hash < hash { low = mid + 1 } else { high = mid }
        }
        var cursor = low
        while cursor < extraWords.count, extraWords[cursor].hash == hash {
            let matches = extraWords[cursor].word.withBytes { stored in
                stored.count == bytes.count && stored.elementsEqual(bytes)
            }
            if matches { return true }
            cursor += 1
        }
        return false
    }

    private static func fnv(_ bytes: UnsafeBufferPointer<UInt8>) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in bytes {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return hash
    }

    // MARK: - Continuous Streaming Pipeline (AsyncStream)

    /// Creates an active streaming pipeline receiving touch points and yielding candidate lists.
    /// A newer push invalidates an in-flight older frame before it waits for the decoder actor.
    public func streamCandidates(
        keyCenters: [String: CGPoint],
        language: KeyboardLanguage,
        extraWords: [String] = [],
        beamWidth: Int? = nil,
        wSpatial: Float? = nil,
        wFreq: Float? = nil,
        frameInterval: TimeInterval? = nil
    ) -> (stream: AsyncStream<[Candidate]>, pushPoint: @Sendable (CGPoint, TimeInterval) async -> Void, finish: @Sendable () async -> Void) {
        // Configure synchronously on the actor before returning push closures. This avoids
        // the prior race where an unstructured setup Task could run after the first touch.
        try? configure(
            keyCenters: keyCenters,
            language: language,
            extraWords: extraWords,
            beamWidth: beamWidth,
            wSpatial: wSpatial,
            wFreq: wFreq,
            frameInterval: frameInterval
        )

        var continuation: AsyncStream<[Candidate]>.Continuation?
        let stream = AsyncStream<[Candidate]> { continuation = $0 }
        guard let output = continuation else {
            return (stream, { _, _ in }, {})
        }
        let epoch = GlideFrameEpoch()

        let push: @Sendable (CGPoint, TimeInterval) async -> Void = { [weak self] point, timestamp in
            guard let self else { return }
            let generation = epoch.advance()
            do {
                let candidates = try await self.processTouchFrame(
                    point: point,
                    timestamp: timestamp,
                    epoch: epoch,
                    expectedEpoch: generation
                )
                guard epoch.isCurrent(generation), !Task.isCancelled else { return }
                output.yield(candidates)
            } catch is CancellationError {
                // A stale frame was superseded by a newer touch event.
            } catch {
                // A failed frame must not terminate the continuous input stream.
            }
        }

        let finish: @Sendable () async -> Void = { [weak self] in
            epoch.invalidate()
            await self?.resetBeam()
            output.finish()
        }
        return (stream, push, finish)
    }

    /// Streaming pipeline consuming an AsyncStream of CGPoints and yielding Candidate arrays.
    public func streamCandidates(
        points: AsyncStream<CGPoint>,
        keyCenters: [String: CGPoint],
        language: KeyboardLanguage,
        extraWords: [String] = [],
        beamWidth: Int? = nil,
        wSpatial: Float? = nil,
        wFreq: Float? = nil
    ) -> AsyncStream<[Candidate]> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    try await self.configure(
                        keyCenters: keyCenters,
                        language: language,
                        extraWords: extraWords,
                        beamWidth: beamWidth,
                        wSpatial: wSpatial,
                        wFreq: wFreq
                    )
                    var index: TimeInterval = 0
                    for await point in points {
                        try Task.checkCancellation()
                        let candidates = try await self.processTouchFrame(point: point, timestamp: index)
                        try Task.checkCancellation()
                        index += 0.008
                        continuation.yield(candidates)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Legacy Compatibility API

    public func decode(
        points: [CGPoint],
        keyCenters: [String: CGPoint],
        language: KeyboardLanguage,
        extraWords: [String] = [],
        limit: Int = 3
    ) async throws -> [String] {
        try Task.checkCancellation()
        await Task.yield()
        try Task.checkCancellation()
        let result = fallbackDecoder.decode(
            points: points,
            keyCenters: keyCenters,
            language: language,
            extraWords: extraWords,
            limit: limit,
            isCancelled: { Task.isCancelled }
        )
        try Task.checkCancellation()
        return result
    }
}
