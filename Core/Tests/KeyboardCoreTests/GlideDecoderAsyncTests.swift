import CoreGraphics
import XCTest
@testable import KeyboardCore

final class GlideDecoderAsyncTests: XCTestCase {
    private func centers(_ language: KeyboardLanguage) -> [String: CGPoint] {
        let layout = KeyboardGeometry.make(bounds: CGRect(x: 0, y: 0, width: 385, height: 225), language: language)
        return Dictionary(uniqueKeysWithValues: layout.keys.compactMap { key in
            guard let letter = key.role.character, letter.allSatisfy(\.isLetter) else { return nil }
            return (letter, key.center)
        })
    }

    func testActorDecodesOffCallerAndReturnsCandidates() async throws {
        let language = KeyboardLanguage.english
        let geometry = centers(language)
        let points = "hello".map { geometry[String($0)]! }
        let actor = GlideDecoderActor()
        let result = try await actor.decode(points: points, keyCenters: geometry, language: language)
        XCTAssertEqual(result.first, "hello")
    }

    func testConcurrentRequestsAreSerializedSafely() async throws {
        let language = KeyboardLanguage.english
        let geometry = centers(language)
        let points = "hello".map { geometry[String($0)]! }
        let actor = GlideDecoderActor()
        async let first = actor.decode(points: points, keyCenters: geometry, language: language)
        async let second = actor.decode(points: points, keyCenters: geometry, language: language)
        let (a, b) = try await (first, second)
        XCTAssertEqual(a.first, "hello")
        XCTAssertEqual(b.first, "hello")
    }

    func testCancellationBeforeScoringThrowsCancellationError() async {
        let actor = GlideDecoderActor()
        let task = Task {
            try await actor.decode(points: [], keyCenters: [:], language: .english)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected: cancellation is checked before and after the actor yield.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPointThrottlerUsesTimeAndSignificantMovement() {
        var throttler = GlidePointThrottler(minimumInterval: 0.03, significantShift: 4)
        XCTAssertTrue(throttler.shouldAccept(CGPoint(x: 0, y: 0), at: 1))
        XCTAssertFalse(throttler.shouldAccept(CGPoint(x: 1, y: 1), at: 1.016))
        XCTAssertTrue(throttler.shouldAccept(CGPoint(x: 4, y: 0), at: 1.016))
        XCTAssertFalse(throttler.shouldAccept(CGPoint(x: 5, y: 0), at: 1.025))
        XCTAssertTrue(throttler.shouldAccept(CGPoint(x: 5, y: 0), at: 1.047))
        throttler.reset()
        XCTAssertTrue(throttler.shouldAccept(CGPoint(x: 5, y: 0), at: 2))
    }
}
