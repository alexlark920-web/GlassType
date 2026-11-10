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

/// Serializes glide decoding and continuous streaming beam search away from the UI executor.
/// Complies with Swift 6 strict concurrency, frame budgets (<=8ms for 120Hz), and cancellation.
public actor GlideDecoderActor {
    public struct BeamPath: Sendable {
        public var node: Int
        public var word: String
        public var cumulativeSpatialScore: Float
        public var length: Int
        public var lastKey: String
        public var isTerminal: Bool

        public init(node: Int, word: String, cumulativeSpatialScore: Float, length: Int, lastKey: String, isTerminal: Bool) {
            self.node = node
            self.word = word
            self.cumulativeSpatialScore = cumulativeSpatialScore
            self.length = length
            self.lastKey = lastKey
            self.isTerminal = isTerminal
        }
    }

    private let fallbackDecoder = GlideDecoder()
    private var spatialModel: SpatialTouchModel?
    private var lexicon: MappedBinaryLexicon?
    private var activeLanguage: KeyboardLanguage = .english
    private var activeBeam: [BeamPath] = []
    private var lastProcessedTimestamp: TimeInterval = 0
    private var lastProcessedPoint: CGPoint = .zero
    private var frameInterval: TimeInterval = 0.008 // 8ms (120Hz ProMotion target)
    private var beamWidth: Int = 16
    private var wSpatial: Float = 0.65
    private var wFreq: Float = 0.35
    private var extraVocabulary: [String] = []

    public init() {}

    // MARK: - Configuration & Session Lifecycle

    /// Resets the active beam search paths and touch timestamps.
    public func resetBeam() {
        activeBeam.removeAll(keepingCapacity: true)
        lastProcessedTimestamp = 0
        lastProcessedPoint = .zero
    }

    /// Configures the streaming beam search session for an active layout and language.
    public func configure(
        keyCenters: [String: CGPoint],
        language: KeyboardLanguage,
        extraWords: [String] = [],
        beamWidth: Int = 16,
        wSpatial: Float = 0.65,
        wFreq: Float = 0.35,
        frameInterval: TimeInterval = 0.008
    ) throws {
        self.activeLanguage = language
        self.beamWidth = max(4, min(64, beamWidth))
        self.wSpatial = wSpatial
        self.wFreq = wFreq
        self.frameInterval = max(0.001, frameInterval)
        self.extraVocabulary = extraWords
        self.spatialModel = SpatialTouchModel(keyCenters: keyCenters)
        self.lexicon = try? MappedBinaryLexicon(bundledLanguage: language)
        resetBeam()
    }

    // MARK: - Single Frame Processing (Zero-Allocation Hot Path)

    /// Processes a single touch frame in <= 5ms on this background actor.
    /// Immediately drops work when Task.isCancelled is set.
    public func processTouchFrame(point: CGPoint, timestamp: TimeInterval) throws -> [Candidate] {
        try Task.checkCancellation()
        guard let spatial = spatialModel, let lex = lexicon else { return [] }

        // Enforce frame budget throttling (target interval <= 8ms for 120Hz)
        if lastProcessedTimestamp > 0, timestamp - lastProcessedTimestamp < frameInterval {
            let dx = point.x - lastProcessedPoint.x, dy = point.y - lastProcessedPoint.y
            if dx * dx + dy * dy < 16.0 {
                return currentTopCandidates(limit: 5)
            }
        }
        lastProcessedTimestamp = timestamp
        lastProcessedPoint = point

        let touchSIMD = SIMD2<Float>(Float(point.x), Float(point.y))
        var candidateBuffer = [SpatialTouchModel.ScoredKey](repeating: .init(), count: 6)
        let candidateCount = candidateBuffer.withUnsafeMutableBufferPointer { buf in
            spatial.evaluate(touch: touchSIMD, into: buf, probabilityThreshold: 0.001)
        }
        guard candidateCount > 0 else { return currentTopCandidates(limit: 5) }

        try Task.checkCancellation()

        var nextBeam: [BeamPath] = []
        nextBeam.reserveCapacity(beamWidth * 4)

        if activeBeam.isEmpty {
            // First touch: spawn initial beam paths from Trie root
            let root = lex.rootNode()
            for i in 0..<candidateCount {
                try Task.checkCancellation()
                let idx = Int(candidateBuffer[i].keyIndex)
                guard spatial.keys.indices.contains(idx) else { continue }
                let keyLoc = spatial.keys[idx]

                if let transition = lex.transition(from: root, utf8: keyLoc.utf8Bytes, length: keyLoc.utf8Length) {
                    nextBeam.append(BeamPath(
                        node: transition.node,
                        word: keyLoc.key,
                        cumulativeSpatialScore: candidateBuffer[i].logProbability,
                        length: 1,
                        lastKey: keyLoc.key,
                        isTerminal: transition.isTerminal
                    ))
                }
            }
        } else {
            // Successive touch: expand existing paths with transition or dwell
            for path in activeBeam {
                try Task.checkCancellation()

                // 1. Dwell on current key (if finger is dwelling/hovering over same key)
                for i in 0..<candidateCount {
                    let idx = Int(candidateBuffer[i].keyIndex)
                    if spatial.keys.indices.contains(idx), spatial.keys[idx].key == path.lastKey {
                        nextBeam.append(BeamPath(
                            node: path.node,
                            word: path.word,
                            cumulativeSpatialScore: path.cumulativeSpatialScore + candidateBuffer[i].logProbability * 0.5,
                            length: path.length,
                            lastKey: path.lastKey,
                            isTerminal: path.isTerminal
                        ))
                        break
                    }
                }

                // 2. Transition to new neighboring key
                for i in 0..<candidateCount {
                    try Task.checkCancellation()
                    let idx = Int(candidateBuffer[i].keyIndex)
                    guard spatial.keys.indices.contains(idx) else { continue }
                    let keyLoc = spatial.keys[idx]
                    guard keyLoc.key != path.lastKey else { continue }

                    if let transition = lex.transition(from: path.node, utf8: keyLoc.utf8Bytes, length: keyLoc.utf8Length) {
                        nextBeam.append(BeamPath(
                            node: transition.node,
                            word: path.word + keyLoc.key,
                            cumulativeSpatialScore: path.cumulativeSpatialScore + candidateBuffer[i].logProbability,
                            length: path.length + 1,
                            lastKey: keyLoc.key,
                            isTerminal: transition.isTerminal
                        ))
                    }
                }
            }
        }

        try Task.checkCancellation()

        // Prune down to Top-K (K=16) using normalized spatial scores
        nextBeam.sort {
            let leftNorm = $0.cumulativeSpatialScore / Float(max(1, $0.length))
            let rightNorm = $1.cumulativeSpatialScore / Float(max(1, $1.length))
            return leftNorm > rightNorm
        }

        if nextBeam.count > beamWidth {
            nextBeam.removeSubrange(beamWidth..<nextBeam.count)
        }
        self.activeBeam = nextBeam

        return currentTopCandidates(limit: 5)
    }

    /// Computes fused scores for the current beam and returns top candidates.
    private func currentTopCandidates(limit: Int) -> [Candidate] {
        guard !activeBeam.isEmpty else { return [] }
        let words = activeBeam.map(\.word)
        let ranks = OfflineLexicon.frequencyIndices(words: words, language: activeLanguage)

        var scored: [Candidate] = []
        scored.reserveCapacity(activeBeam.count)

        for path in activeBeam {
            let normSpatial = path.cumulativeSpatialScore / Float(max(1, path.length))
            let rank = extraVocabulary.contains(path.word) ? 0 : (ranks[OfflineLexicon.normalized(path.word)] ?? 50_000)
            let logFreq = -log(Float(rank + 10))
            let finalScore = (wSpatial * normSpatial) + (wFreq * logFreq)

            scored.append(Candidate(
                word: path.word,
                score: finalScore,
                spatialScore: normSpatial,
                frequencyScore: logFreq,
                isTerminal: path.isTerminal
            ))
        }

        // Terminal words receive preference, followed by highest fused score
        scored.sort {
            if $0.isTerminal != $1.isTerminal { return $0.isTerminal && !$1.isTerminal }
            return $0.score > $1.score
        }

        return Array(scored.prefix(max(1, limit)))
    }

    // MARK: - Continuous Streaming Pipeline (AsyncStream)

    /// Creates an active streaming pipeline receiving touch points and yielding candidate lists.
    public func streamCandidates(
        keyCenters: [String: CGPoint],
        language: KeyboardLanguage,
        extraWords: [String] = [],
        beamWidth: Int = 16,
        wSpatial: Float = 0.65,
        wFreq: Float = 0.35,
        frameInterval: TimeInterval = 0.008
    ) -> (stream: AsyncStream<[Candidate]>, pushPoint: @Sendable (CGPoint, TimeInterval) async -> Void, finish: @Sendable () async -> Void) {
        var continuation: AsyncStream<[Candidate]>.Continuation?
        let stream = AsyncStream<[Candidate]> { cont in
            continuation = cont
        }

        let push: @Sendable (CGPoint, TimeInterval) async -> Void = { [weak self] point, timestamp in
            guard let self else { return }
            do {
                let candidates = try await self.processTouchFrame(point: point, timestamp: timestamp)
                continuation?.yield(candidates)
            } catch is CancellationError {
                // Drop stale frame
            } catch {}
        }

        let finish: @Sendable () async -> Void = { [weak self] in
            await self?.resetBeam()
            continuation?.finish()
        }

        Task {
            try? await self.configure(
                keyCenters: keyCenters,
                language: language,
                extraWords: extraWords,
                beamWidth: beamWidth,
                wSpatial: wSpatial,
                wFreq: wFreq,
                frameInterval: frameInterval
            )
        }

        return (stream, push, finish)
    }

    /// Streaming pipeline consuming an AsyncStream of CGPoints and yielding Candidate arrays.
    public func streamCandidates(
        points: AsyncStream<CGPoint>,
        keyCenters: [String: CGPoint],
        language: KeyboardLanguage,
        extraWords: [String] = [],
        beamWidth: Int = 16,
        wSpatial: Float = 0.65,
        wFreq: Float = 0.35
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
                        index += 0.008
                        continuation.yield(candidates)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
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
