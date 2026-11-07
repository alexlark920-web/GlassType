import XCTest
@testable import KeyboardCore

final class SpacebarInteractionTests: XCTestCase {
    private func started() -> SpacebarInteraction {
        var gesture = SpacebarInteraction()
        gesture.begin(x: 100, y: 20, at: 0)
        return gesture
    }
    func testTapInsertsExactlyOneSpace() {
        var gesture = started()
        XCTAssertEqual(gesture.end(x: 100, y: 20, at: 0.1), .insertSpace)
        XCTAssertEqual(gesture.end(x: 100, y: 20, at: 0.12), .none)
        XCTAssertEqual(gesture.phase, .idle)
    }
    func testSmallFingerJitterStillAllowsTap() {
        var gesture = started()
        XCTAssertEqual(gesture.update(x: 107, y: 24, at: 0.06), .none)
        XCTAssertEqual(gesture.end(x: 108, y: 23, at: 0.13), .insertSpace)
    }
    func testQuickLeftSwipeChangesToNextLanguageWithoutSpace() {
        var gesture = started()
        XCTAssertEqual(gesture.update(x: 58, y: 23, at: 0.12), .none)
        XCTAssertEqual(gesture.end(x: 40, y: 24, at: 0.20), .changeLanguage(.next))
    }
    func testQuickRightSwipeChangesToPreviousLanguage() {
        var gesture = started()
        XCTAssertEqual(gesture.end(x: 150, y: 22, at: 0.18), .changeLanguage(.previous))
    }
    func testSwipeCommitsOnlyAtReleaseAndOnlyOnce() {
        var gesture = started()
        for (x, time) in [(60.0, 0.10), (40, 0.15), (20, 0.2)] {
            XCTAssertEqual(gesture.update(x: x, y: 20, at: time), .none)
        }
        XCTAssertEqual(gesture.end(x: 10, y: 20, at: 0.25), .changeLanguage(.next))
        XCTAssertEqual(gesture.hold(at: 0.6), .none)
        XCTAssertEqual(gesture.end(x: 10, y: 20, at: 0.7), .none)
    }
    func testSlowDragDoesNotChangeLanguageOrInsertSpace() {
        var gesture = started()
        _ = gesture.update(x: 120, y: 20, at: 0.2)
        XCTAssertEqual(gesture.end(x: 160, y: 20, at: 0.5), .none)
    }
    func testVerticalDragIsNotALanguageSwipe() {
        var gesture = started()
        _ = gesture.update(x: 105, y: 60, at: 0.1)
        XCTAssertEqual(gesture.end(x: 150, y: 80, at: 0.2), .none)
    }
    func testHoldStartsTrackpadOnceWithoutAddingSpace() {
        var gesture = started()
        XCTAssertEqual(gesture.hold(at: 0.3), .none)
        XCTAssertEqual(gesture.hold(at: 0.43), .cursorBegan)
        XCTAssertEqual(gesture.hold(at: 0.6), .none)
        XCTAssertEqual(gesture.end(x: 100, y: 20, at: 0.7), .none)
    }
    func testTrackpadMotionNeverTurnsIntoLanguageSwipe() {
        var gesture = started()
        _ = gesture.hold(at: 0.43)
        XCTAssertEqual(gesture.update(x: 20, y: 20, at: 0.5), .moveCursor(-10))
        XCTAssertEqual(gesture.end(x: 20, y: 20, at: 0.6), .none)
    }
    func testCursorHasDeadbandAndRetainsSubcharacterMotion() {
        var gesture = started()
        _ = gesture.hold(at: 0.43)
        XCTAssertEqual(gesture.update(x: 107, y: 20, at: 0.5), .none)
        XCTAssertEqual(gesture.update(x: 108, y: 20, at: 0.55), .moveCursor(1))
        XCTAssertEqual(gesture.update(x: 115, y: 20, at: 0.6), .none)
        XCTAssertEqual(gesture.update(x: 116, y: 20, at: 0.65), .moveCursor(1))
    }
    func testCursorReversesWithoutAccumulatingRoundingError() {
        var gesture = started()
        _ = gesture.hold(at: 0.43)
        XCTAssertEqual(gesture.update(x: 124, y: 20, at: 0.5), .moveCursor(3))
        XCTAssertEqual(gesture.update(x: 100, y: 20, at: 0.6), .moveCursor(-3))
        XCTAssertEqual(gesture.update(x: 92, y: 20, at: 0.7), .moveCursor(-1))
    }
    func testCursorVerticalMotionDoesNotMoveCaret() {
        var gesture = started()
        _ = gesture.hold(at: 0.43)
        XCTAssertEqual(gesture.update(x: 100, y: 100, at: 0.6), .none)
    }
    func testFinalCursorMovementIsNotLostAtRelease() {
        var gesture = started()
        _ = gesture.hold(at: 0.43)
        XCTAssertEqual(gesture.end(x: 116, y: 20, at: 0.6), .moveCursor(2))
        XCTAssertEqual(gesture.phase, .idle)
    }
    func testCancellingPressSuppressesTimerAndSpace() {
        var gesture = started()
        gesture.cancel()
        XCTAssertEqual(gesture.hold(at: 0.5), .none)
        XCTAssertEqual(gesture.end(x: 100, y: 20, at: 0.6), .none)
    }
    func testCancellingTrackpadStopsCursorMovement() {
        var gesture = started()
        _ = gesture.hold(at: 0.43)
        gesture.cancel()
        XCTAssertEqual(gesture.update(x: 200, y: 20, at: 0.6), .none)
        XCTAssertEqual(gesture.end(x: 200, y: 20, at: 0.7), .none)
    }
    func testShortSwipeReturningToOriginDoesNotTypeSpace() {
        var gesture = started()
        _ = gesture.update(x: 55, y: 20, at: 0.1)
        XCTAssertEqual(gesture.end(x: 100, y: 20, at: 0.2), .none)
    }
    func testEarlyMovementPreventsUnexpectedLongHoldActivation() {
        var gesture = started()
        _ = gesture.update(x: 125, y: 20, at: 0.1)
        XCTAssertEqual(gesture.hold(at: 0.5), .none)
        XCTAssertEqual(gesture.end(x: 125, y: 20, at: 0.6), .none)
    }
    func testDelayedHoldCallbackCannotTurnSwipeIntoTrackpad() {
        var gesture = started()
        _ = gesture.update(x: 55, y: 20, at: 0.12)
        XCTAssertEqual(gesture.hold(at: 0.5), .none)
        XCTAssertEqual(gesture.end(x: 40, y: 20, at: 0.6), .none)
    }
    func testNewTouchResetsPreviousCursorAnchor() {
        var gesture = started()
        _ = gesture.hold(at: 0.43)
        _ = gesture.update(x: 180, y: 20, at: 0.5)
        gesture.begin(x: 50, y: 20, at: 1)
        XCTAssertEqual(gesture.end(x: 50, y: 20, at: 1.1), .insertSpace)
    }
    func testHoldWithoutTimerDoesNotBecomeSpaceAtRelease() {
        var gesture = started()
        XCTAssertEqual(gesture.end(x: 100, y: 20, at: 0.5), .none)
    }
    func testLanguageCyclingWrapsBothDirections() {
        var state = InputState(language: .english)
        let languages: [KeyboardLanguage] = [.english, .russian, .ukrainian]
        state.cycleLanguage(enabled: languages, direction: .previous)
        XCTAssertEqual(state.language, .ukrainian)
        state.cycleLanguage(enabled: languages, direction: .next)
        XCTAssertEqual(state.language, .english)
    }
    func testLanguageCyclingWithOneOrNoEnabledLanguages() {
        var state = InputState(language: .russian)
        state.cycleLanguage(enabled: [.russian], direction: .previous)
        XCTAssertEqual(state.language, .russian)
        state.cycleLanguage(enabled: [], direction: .next)
        XCTAssertEqual(state.language, .russian)
    }
}
