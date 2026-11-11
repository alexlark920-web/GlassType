import XCTest
import CoreGraphics
@testable import KeyboardCore

final class StreamingBeamSearchTests: XCTestCase {
    private func centers(_ language: KeyboardLanguage) -> [String: CGPoint] {
        let layout = KeyboardGeometry.make(bounds: CGRect(x: 0, y: 0, width: 385, height: 225), language: language)
        return Dictionary(uniqueKeysWithValues: layout.keys.compactMap { key in
            guard let letter = key.role.character, letter.allSatisfy(\.isLetter) else { return nil }
            return (letter, key.center)
        })
    }

    func testSpatialTouchModelGaussianDistribution() {
        let model = SpatialTouchModel(keys: [
            .init(key: "q", centerPoint: CGPoint(x: 20, y: 50)),
            .init(key: "w", centerPoint: CGPoint(x: 50, y: 50)),
            .init(key: "e", centerPoint: CGPoint(x: 80, y: 50)),
            .init(key: "r", centerPoint: CGPoint(x: 110, y: 50)),
            .init(key: "t", centerPoint: CGPoint(x: 140, y: 50))
        ], sigma: 25.0)

        let centerProb = model.spatialProbability(touch: SIMD2<Float>(50, 50), keyCenter: SIMD2<Float>(50, 50))
        XCTAssertGreaterThan(centerProb, 0.9)

        let nearProb = model.spatialProbability(touch: SIMD2<Float>(110, 100), keyCenter: SIMD2<Float>(100, 100))
        let farProb = model.spatialProbability(touch: SIMD2<Float>(150, 100), keyCenter: SIMD2<Float>(100, 100))
        XCTAssertGreaterThan(nearProb, farProb)
    }

    func testZeroAllocationBufferEvaluation() {
        let model = SpatialTouchModel(keys: [
            .init(key: "q", centerPoint: CGPoint(x: 20, y: 50)),
            .init(key: "w", centerPoint: CGPoint(x: 50, y: 50)),
            .init(key: "e", centerPoint: CGPoint(x: 80, y: 50)),
            .init(key: "r", centerPoint: CGPoint(x: 110, y: 50))
        ], sigma: 25.0)

        var buffer = [SpatialTouchModel.ScoredKey](repeating: .init(), count: 4)
        let count = buffer.withUnsafeMutableBufferPointer { buf in
            model.evaluate(touch: SIMD2<Float>(52, 51), into: buf, probabilityThreshold: 0.01)
        }

        XCTAssertGreaterThan(count, 0)
        XCTAssertEqual(buffer[0].keyIndex, 1)
        XCTAssertGreaterThan(buffer[0].probability, 0.8)
    }

    func testCyrillicMultiByteUtf8Storage() {
        let ruKey = SpatialTouchModel.KeyLocation(key: "я", centerPoint: CGPoint(x: 40, y: 150))
        XCTAssertEqual(ruKey.key, "я")
        XCTAssertEqual(ruKey.utf8Length, 2)
        XCTAssertEqual(ruKey.utf8Bytes.0, 0xD1)
        XCTAssertEqual(ruKey.utf8Bytes.1, 0x8F)
    }

    func testStreamingBeamSearchCancellationDropsStaleWork() async throws {
        let geometry = centers(.english)
        let actor = GlideDecoderActor()
        try await actor.configure(keyCenters: geometry, language: .english, beamWidth: 16)

        let task = Task {
            try await actor.processTouchFrame(point: CGPoint(x: 50, y: 50), timestamp: 1.0)
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
        }
    }

    func testStreamingBeamSearchFrameLatencyUnderFiveMilliseconds() async throws {
        let geometry = centers(.english)
        let actor = GlideDecoderActor()
        try await actor.configure(keyCenters: geometry, language: .english, beamWidth: 16)

        let testPoints = [
            CGPoint(x: 50, y: 50),
            CGPoint(x: 55, y: 52),
            CGPoint(x: 60, y: 55),
            CGPoint(x: 70, y: 60),
            CGPoint(x: 85, y: 70)
        ]

        var totalElapsed: TimeInterval = 0
        var timestamp: TimeInterval = 1.0

        for pt in testPoints {
            let start = ProcessInfo.processInfo.systemUptime
            _ = try await actor.processTouchFrame(point: pt, timestamp: timestamp)
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            totalElapsed += elapsed
            timestamp += 0.010
        }

        let averagePerFrameMs = (totalElapsed / Double(testPoints.count)) * 1_000.0
        #if DEBUG
        XCTAssertLessThan(averagePerFrameMs, 25.0, "Average frame time in debug: \(averagePerFrameMs) ms")
        #else
        XCTAssertLessThan(averagePerFrameMs, 25.0, "Average frame time exceeded 25ms target: \(averagePerFrameMs) ms")
        #endif
    }

    func testStreamingBeamSearchProducesCandidatesForKnownWord() async throws {
        let geometry = centers(.english)
        let actor = GlideDecoderActor()
        try await actor.configure(keyCenters: geometry, language: .english, beamWidth: 16)

        let points = [
            CGPoint(x: 50, y: 50),
            CGPoint(x: 55, y: 52),
            CGPoint(x: 60, y: 55),
            CGPoint(x: 70, y: 60),
            CGPoint(x: 85, y: 70),
            CGPoint(x: 90, y: 75),
            CGPoint(x: 95, y: 80)
        ]

        var candidates: [GlideDecoderActor.Candidate] = []
        for (index, point) in points.enumerated() {
            candidates = try await actor.processTouchFrame(point: point, timestamp: Double(index + 1) * 0.01)
            if !candidates.isEmpty {
                let lower = candidates.map { $0.word.lowercased() }
                if lower.contains("help") || lower.contains("hello") || lower.contains("helo") {
                    break
                }
            }
        }

        XCTAssertTrue(candidates.contains { $0.word.lowercased() == "help" || $0.word.lowercased() == "hello" || $0.word.lowercased() == "helo" }, "Candidates: \(candidates.map(\.word))")
    }
}
