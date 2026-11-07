import Foundation
import XCTest
@testable import KeyboardCore

final class InputResponsivenessTests: XCTestCase {
    func testFirstKeyIsRefreshedAfterMessageWasClearedWithoutCallback() {
        var state = InputState()
        _ = state.inserted("hello")
        XCTAssertEqual(state.shift, .off)
        // Commit path reads fresh proxy context before calling inserted.
        state.synchronize(context: "", autoCapitalization: true, fieldIsEmpty: true)
        XCTAssertEqual(state.inserted("п"), "П")
    }
    func testEmptyBackingStoreSupportsNilAndStaleProxyContext() {
        let contexts: [String?] = [nil, "old message"]
        for context in contexts {
            var state = InputState(); _ = state.inserted("old")
            state.synchronize(context: context, autoCapitalization: true, fieldIsEmpty: true)
            XCTAssertEqual(state.inserted("ї"), "Ї")
        }
    }
    func testNilContextAloneDoesNotCapitalizeAnExistingWord() {
        var state = InputState(); _ = state.inserted("m")
        state.synchronize(context: nil, autoCapitalization: true, fieldIsEmpty: false)
        XCTAssertEqual(state.inserted("i"), "i")
    }
    func testUnknownNonemptyFieldDropsInitialAutomaticShiftButKeepsManualShift() {
        var state = InputState()
        state.synchronize(context: nil, autoCapitalization: true, fieldIsEmpty: false)
        XCTAssertEqual(state.inserted("a"), "a")
        state.tapShift(at: 2)
        state.synchronize(context: nil, autoCapitalization: true, fieldIsEmpty: false)
        XCTAssertEqual(state.inserted("b"), "B")
    }
    func testLeadingQuotesWhitespaceAndEmojiPreserveFirstLetterShift() {
        for prefix in ["\"", "«", "  ", "👋 ", "🙂\n  "] {
            var state = InputState()
            _ = state.inserted(prefix)
            state.synchronize(context: prefix, autoCapitalization: true)
            XCTAssertEqual(state.inserted("п"), "П", prefix)
        }
    }
    func testPunctuationDoesNotConsumeManualOneShotShift() {
        var state = InputState(); _ = state.inserted("a")
        state.tapShift(at: 2)
        _ = state.inserted("'")
        XCTAssertEqual(state.inserted("e"), "E")
        XCTAssertEqual(state.inserted("f"), "f")
    }
    func testGlideAndSuggestedWordsUseSentenceCaseRatherThanAllCaps() {
        for word in ["hello", "привет", "привіт"] {
            var state = InputState()
            XCTAssertEqual(state.insertedWord(word), word.capitalized)
            XCTAssertEqual(state.insertedWord(word), word)
        }
    }
    func testCapsLockStillUppercasesWholeWord() {
        var state = InputState(); state.tapShift(at: 1); state.tapShift(at: 1.1)
        state.synchronize(context: nil, autoCapitalization: true, fieldIsEmpty: true)
        XCTAssertEqual(state.insertedWord("hello"), "HELLO")
        XCTAssertEqual(state.shift, .locked)
    }
    func testDisabledCapitalizationAndHostURLPolicyRemainRespected() {
        var state = InputState()
        state.synchronize(context: nil, autoCapitalization: false)
        XCTAssertEqual(state.inserted("h"), "h")
        state.synchronize(context: "", autoCapitalization: false, fieldIsEmpty: true)
        XCTAssertEqual(state.insertedWord("hello"), "hello")
    }
    func testBackspaceStartsSoonerAndAcceleratesWithFiniteIntervals() {
        XCTAssertEqual(BackspaceRepeat.initialDelay, 0.16, accuracy: 1e-8)
        XCTAssertEqual(BackspaceRepeat.interval(heldFor: 0.16), 0.055, accuracy: 1e-8)
        XCTAssertLessThan(BackspaceRepeat.interval(heldFor: 1), BackspaceRepeat.interval(heldFor: 0.16))
        XCTAssertLessThan(BackspaceRepeat.interval(heldFor: 3), BackspaceRepeat.interval(heldFor: 1))
        for elapsed in [Double.nan, .infinity, -1, 0, 1, 100] {
            XCTAssertGreaterThanOrEqual(BackspaceRepeat.interval(heldFor: elapsed), 0.03)
            XCTAssertLessThanOrEqual(BackspaceRepeat.interval(heldFor: elapsed), 0.055)
        }
    }
}
