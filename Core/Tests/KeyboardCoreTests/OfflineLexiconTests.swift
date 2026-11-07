import Foundation
import XCTest
@testable import KeyboardCore

final class OfflineLexiconTests: XCTestCase {
    func testAllResourcesAreBundledAndContainLargeRealCorpora() {
        XCTAssertGreaterThanOrEqual(OfflineLexicon.words(language: .english).count, 30_000)
        XCTAssertGreaterThanOrEqual(OfflineLexicon.words(language: .russian).count, 30_000)
        XCTAssertGreaterThan(OfflineLexicon.words(language: .ukrainian).count, 25_000)
        for language in KeyboardLanguage.allCases {
            let words = OfflineLexicon.words(language: language)
            XCTAssertEqual(Set(words).count, words.count)
            XCTAssertTrue(words.allSatisfy { (2...24).contains($0.count) })
        }
    }
    func testConversationalWordsAndLanguageSpecificLettersArePresent() {
        for word in ["hello", "thanks", "keyboard", "tomorrow"] { XCTAssertTrue(OfflineLexicon.contains(word, language: .english), word) }
        for word in ["привет", "как", "спасибо", "сегодня", "клавиатура", "свайп"] { XCTAssertTrue(OfflineLexicon.contains(word, language: .russian), word) }
        for word in ["привіт", "як", "дякую", "сьогодні", "клавіатура", "свайп"] { XCTAssertTrue(OfflineLexicon.contains(word, language: .ukrainian), word) }
        XCTAssertTrue(OfflineLexicon.contains("HELLO", language: .english))
        XCTAssertFalse(OfflineLexicon.contains("this-is-not-a-real-word-123", language: .english))
        XCTAssertFalse(OfflineLexicon.contains("привет", language: .ukrainian))
    }
    func testEditDistanceCandidatesAreLocalBoundedAndPreserveKnownWords() {
        let candidates = OfflineLexicon.correctionCandidates(for: "keybaord", language: .english)
        XCTAssertTrue(candidates.contains("keyboard"))
        XCTAssertTrue(candidates.allSatisfy { AutocorrectionEngine.isSingleEdit("keybaord", $0) })
        XCTAssertLessThanOrEqual(candidates.count, 8)
        XCTAssertTrue(OfflineLexicon.correctionCandidates(for: "hello", language: .english).isEmpty)
        XCTAssertTrue(OfflineLexicon.correctionCandidates(for: "http://example", language: .english).isEmpty)
        XCTAssertTrue(OfflineLexicon.correctionCandidates(for: "keybaord", language: .english, limit: 0).isEmpty)
    }
    func testLicensesAreAvailableOffline() {
        XCTAssertTrue(OfflineLexicon.licenseNotice.contains("CC BY-SA 4.0"))
        XCTAssertTrue(OfflineLexicon.licenseNotice.contains("Hermit Dave"))
    }
    func testPrefixCompletionsUseTheWholeCorpusAndFrequencyOrder() {
        XCTAssertEqual(OfflineLexicon.completions(prefix: "HE", language: .english), ["here", "her", "hey"])
        XCTAssertTrue(OfflineLexicon.completions(prefix: "keyb", language: .english).contains("keyboard"))
        XCTAssertTrue(OfflineLexicon.completions(prefix: "клав", language: .russian).contains("клавиатура"))
        XCTAssertTrue(OfflineLexicon.completions(prefix: "клав", language: .ukrainian).contains("клавіатура"))
        XCTAssertTrue(OfflineLexicon.completions(prefix: "hello ", language: .english).isEmpty)
        XCTAssertTrue(OfflineLexicon.completions(prefix: "h", language: .english, limit: 0).isEmpty)
    }
    func testUIQueriesNeverConstructAnEvictedLanguage() {
        // Drive the bounded two-language cache through two complete rotations.
        for _ in 0..<2 { for language in KeyboardLanguage.allCases { _ = OfflineLexicon.words(language: language) } }
        XCTAssertFalse(OfflineLexicon.isPrepared(language: .english))
        XCTAssertTrue(OfflineLexicon.completions(prefix: "he", language: .english, cachedOnly: true).isEmpty)
        XCTAssertNil(OfflineLexicon.preparedCheck("hello", language: .english))
        XCTAssertFalse(OfflineLexicon.isPrepared(language: .english))
        _ = OfflineLexicon.words(language: .english)
        XCTAssertEqual(OfflineLexicon.preparedCheck("hello", language: .english)?.known, true)
        XCTAssertTrue(OfflineLexicon.preparedCheck("keybaord", language: .english)?.candidates.contains("keyboard") == true)
    }

}
