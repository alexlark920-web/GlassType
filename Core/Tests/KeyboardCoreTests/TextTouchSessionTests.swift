import Foundation
import CoreGraphics
import XCTest
@testable import KeyboardCore

final class TextTouchSessionTests: XCTestCase {
    private func model(_ language: KeyboardLanguage = .english, width: CGFloat = 393, height: CGFloat = 229.7) -> TouchRecognizer {
        TouchRecognizer(geometry: KeyboardGeometry.make(bounds: CGRect(x: 0, y: 0, width: width, height: height), language: language))
    }
    func testTapCommitsOnceAndCancellationNeverCommits() {
        let m = model(), key = m.geometry.keys[3]
        var session = TextTouchSession()
        session.begin(at: key.center, keyIndex: key.index, model: m)
        XCTAssertEqual(session.end(at: key.center, model: m), key.index)
        XCTAssertNil(session.end(at: key.center, model: m))
        session.begin(at: key.center, keyIndex: key.index, model: m)
        session.cancel()
        XCTAssertNil(session.end(at: key.center, model: m))
    }
    func testSmallBoundaryJitterKeepsInitialKey() {
        let m = model(), left = m.geometry.keys[3], right = m.geometry.keys[4]
        let boundary = (left.center.x + right.center.x) / 2
        var session = TextTouchSession()
        session.begin(at: CGPoint(x: boundary - 0.2, y: left.center.y), keyIndex: left.index, model: m)
        let offsets: [CGFloat] = [0.2, -0.1, 0.4, -0.2, 0.3]
        for dx in offsets {
            XCTAssertEqual(session.move(to: CGPoint(x: boundary + dx, y: left.center.y), model: m), left.index)
        }
        XCTAssertEqual(session.end(at: CGPoint(x: boundary + 0.3, y: left.center.y), model: m), left.index)
    }
    func testDeliberateSlideRetargetsToAdjacentCharacterInAllLayouts() {
        for language in KeyboardLanguage.allCases {
            for size in [CGSize(width: 320, height: 229.7), CGSize(width: 393, height: 229.7), CGSize(width: 734, height: 155)] {
                let m = model(language, width: size.width, height: size.height)
                let a = m.geometry.keys[3], b = m.geometry.keys[4]
                var session = TextTouchSession()
                session.begin(at: a.center, keyIndex: a.index, model: m)
                XCTAssertEqual(session.move(to: b.center, model: m), b.index)
                XCTAssertEqual(session.end(at: b.center, model: m), b.index)
            }
        }
    }
    func testFunctionCellsCannotBeEnteredBySlidingACharacter() {
        let m = model(), letter = m.geometry.keys[3]
        for key in m.geometry.keys where key.role.character == nil {
            var session = TextTouchSession()
            session.begin(at: letter.center, keyIndex: letter.index, model: m)
            XCTAssertNil(session.end(at: key.center, model: m))
        }
    }
    func testReturnFromOutsideCanRecoverButFarReleaseCancels() {
        let m = model(), key = m.geometry.keys[0]
        var session = TextTouchSession()
        session.begin(at: key.center, keyIndex: key.index, model: m)
        XCTAssertNil(session.move(to: CGPoint(x: -40, y: 20), model: m))
        XCTAssertEqual(session.move(to: key.center, model: m), key.index)
        XCTAssertNil(session.end(at: CGPoint(x: -40, y: 20), model: m))
    }
    func testNearOuterEdgeLiftDoesNotLoseCharacter() {
        let m = model(), key = m.geometry.keys[0]
        var session = TextTouchSession()
        session.begin(at: CGPoint(x: 1, y: key.center.y), keyIndex: key.index, model: m)
        XCTAssertEqual(session.end(at: CGPoint(x: -2, y: key.center.y), model: m), key.index)
    }
    func testTwoFingersHaveIndependentSelections() {
        let m = model(), a = m.geometry.keys[2], b = m.geometry.keys[7]
        var first = TextTouchSession(), second = TextTouchSession()
        first.begin(at: a.center, keyIndex: a.index, model: m)
        second.begin(at: b.center, keyIndex: b.index, model: m)
        XCTAssertEqual(second.end(at: b.center, model: m), b.index)
        XCTAssertEqual(first.end(at: a.center, model: m), a.index)
    }
    func testInvalidSampleAndRestartAreSafe() {
        let m = model(), key = m.geometry.keys[3]
        var session = TextTouchSession()
        session.begin(at: CGPoint(x: CGFloat.nan, y: 0), keyIndex: key.index, model: m)
        XCTAssertNotEqual(session.phase, .tracking)
        session.begin(at: key.center, keyIndex: key.index, model: m)
        XCTAssertNil(session.end(at: CGPoint(x: CGFloat.nan, y: 0), model: m))
        session.begin(at: key.center, keyIndex: key.index, model: m)
        XCTAssertEqual(session.end(at: key.center, model: m), key.index)
    }
    func testGlideThresholdRejectsJitterAndShortTraceFallbackIsBounded() {
        let pitch = CGSize(width: 32, height: 56), start = CGPoint.zero
        let threshold = GlideActivation.minimumTravel(keyPitch: pitch)
        XCTAssertGreaterThanOrEqual(threshold, 12)
        XCTAssertFalse(GlideActivation.shouldBegin(start: start, current: CGPoint(x: 8, y: 0), startKey: 1, currentKey: 2, minimumDistance: threshold))
        XCTAssertTrue(GlideActivation.shouldBegin(start: start, current: CGPoint(x: 32, y: 0), startKey: 1, currentKey: 2, minimumDistance: threshold))
        XCTAssertTrue(GlideActivation.isShortStroke([start, CGPoint(x: 16, y: 0)], keyPitch: pitch))
        XCTAssertFalse(GlideActivation.isShortStroke([start, CGPoint(x: 32, y: 0)], keyPitch: pitch))
        XCTAssertFalse(GlideActivation.isShortStroke([start, CGPoint(x: 32, y: 0), start], keyPitch: pitch))
    }
}
