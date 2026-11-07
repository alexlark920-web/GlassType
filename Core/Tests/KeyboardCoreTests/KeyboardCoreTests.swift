import XCTest
@testable import KeyboardCore

final class KeyboardCoreTests: XCTestCase {
    func testEveryLanguageHasThreeUniqueRows() {
        for language in KeyboardLanguage.allCases {
            XCTAssertEqual(language.rows.count, 3)
            let keys = language.rows.flatMap { $0 }
            XCTAssertEqual(keys.count, Set(keys).count)
            XCTAssertTrue(keys.allSatisfy { $0.count == 1 })
        }
    }
    func testUkrainianAlphabetIncludesSpecificLettersAndAlternativeGhe() {
        let keys = KeyboardLanguage.ukrainian.rows.flatMap { $0 }
        for key in ["і", "ї", "є"] { XCTAssertTrue(keys.contains(key)) }
        XCTAssertEqual(KeyboardLanguage.ukrainian.alternatives(for: "г"), ["ґ"])
        XCTAssertFalse(keys.contains("ы"))
    }
    func testRussianYoAvailableOnHold() {
        XCTAssertEqual(KeyboardLanguage.russian.alternatives(for: "е"), ["ё"])
        XCTAssertTrue(KeyboardLanguage.russian.rows.flatMap { $0 }.contains("ъ"))
    }
    func testOneShotShift() {
        var state = InputState()
        XCTAssertEqual(state.inserted("ї"), "Ї")
        XCTAssertEqual(state.inserted("є"), "є")
        XCTAssertEqual(state.shift, .off)
    }
    func testDoubleTapLocksAndSingleTapUnlocks() {
        var state = InputState()
        state.tapShift(at: 1); state.tapShift(at: 1.2)
        XCTAssertEqual(state.shift, .locked)
        XCTAssertEqual(state.inserted("й"), "Й")
        XCTAssertEqual(state.inserted("a"), "A")
        state.tapShift(at: 2)
        XCTAssertEqual(state.shift, .off)
    }
    func testSlowTapDoesNotLock() {
        var state = InputState()
        state.tapShift(at: 1); state.tapShift(at: 2)
        XCTAssertEqual(state.shift, .once)
    }
    func testInsertionResetsDoubleTapWindow() {
        var state = InputState()
        state.tapShift(at: 1); _ = state.inserted("a"); state.tapShift(at: 1.1)
        XCTAssertEqual(state.shift, .once)
    }
    func testLanguageRotationUsesOnlyEnabledLanguages() {
        var state = InputState(language: .russian)
        state.nextLanguage(enabled: [.russian, .ukrainian])
        XCTAssertEqual(state.language, .ukrainian)
        state.nextLanguage(enabled: [.russian, .ukrainian])
        XCTAssertEqual(state.language, .russian)
    }
    func testEmptyLanguageListIsSafe() {
        var state = InputState(); state.nextLanguage(enabled: [])
        XCTAssertEqual(state.language, .english)
    }
    func testUnknownCurrentLanguageStartsAtFirstEnabled() {
        var state = InputState(); state.nextLanguage(enabled: [.ukrainian])
        XCTAssertEqual(state.language, .ukrainian)
    }
    func testAutoCapitalizationAndUnavailableHostContext() {
        var state = InputState(); _ = state.inserted("a")
        state.synchronize(context: nil, autoCapitalization: true)
        XCTAssertEqual(state.shift, .off)
        state.synchronize(context: "hello. ", autoCapitalization: false)
        XCTAssertEqual(state.shift, .off)
        state.synchronize(context: "hello. ", autoCapitalization: true)
        XCTAssertEqual(state.shift, .once)
    }
    func testLockedShiftSurvivesContextChanges() {
        var state = InputState(); state.tapShift(at: 0); state.tapShift(at: 0.1)
        state.synchronize(context: "", autoCapitalization: true)
        XCTAssertEqual(state.shift, .locked)
    }
    func testSuggestionsForEachLanguage() {
        let provider = LocalSuggestionProvider()
        XCTAssertEqual(provider.suggestions(context: "say he", language: .english), ["hello", "help", "here"])
        XCTAssertTrue(provider.suggestions(context: "при", language: .russian).contains("привет"))
        XCTAssertTrue(provider.suggestions(context: "при", language: .ukrainian).contains("привіт"))
    }
    func testNoSuggestionsAfterWhitespaceOrEmoji() {
        let provider = LocalSuggestionProvider()
        for context in ["", "hello ", "hello!", "👨‍👩‍👧‍👦"] {
            XCTAssertTrue(provider.suggestions(context: context, language: .english).isEmpty)
        }
    }
    func testSuggestionsAreBoundedAndCaseInsensitive() {
        let provider = LocalSuggestionProvider()
        XCTAssertLessThanOrEqual(provider.suggestions(context: "h", language: .english).count, 3)
        XCTAssertEqual(provider.suggestions(context: "HE", language: .english), ["hello", "help", "here"])
        XCTAssertTrue(provider.suggestions(context: String(repeating: "a", count: 100_000), language: .english).isEmpty)
    }
    func testReplacementCountsCharactersNotUTF16Units() {
        XCTAssertEqual(LocalSuggestionProvider.trailingWord(in: "👨‍👩‍👧‍👦 привіт"), "привіт")
        XCTAssertEqual(LocalSuggestionProvider.trailingWord(in: "cafe\u{301}"), "cafe\u{301}")
        XCTAssertEqual(LocalSuggestionProvider.trailingWord(in: "hello "), "")
    }
    func testAutomaticShiftFollowsCursorSentencePosition() {
        var state = InputState()
        state.synchronize(context: "middle of word", autoCapitalization: true)
        XCTAssertEqual(state.shift, .off)
        state.synchronize(context: "Done! ", autoCapitalization: true)
        XCTAssertEqual(state.inserted("я"), "Я")
        state.synchronize(context: "New paragraph\n", autoCapitalization: true)
        XCTAssertEqual(state.inserted("ї"), "Ї")
    }
    func testManualOneShotShiftSurvivesMidwordContextRefresh() {
        var state = InputState()
        _ = state.inserted("a")
        state.tapShift(at: 10)
        state.synchronize(context: "inside", autoCapitalization: true)
        XCTAssertEqual(state.inserted("a"), "A")
    }

}
