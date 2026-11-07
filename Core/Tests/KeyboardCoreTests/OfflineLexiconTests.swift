import Foundation
import XCTest
@testable import KeyboardCore

final class OfflineLexiconTests: XCTestCase {
    func testAllResourcesAreBundledAndContainLargeRealCorpora() {
        XCTAssertEqual(OfflineLexicon.words(language: .english).count, 30_000)
        XCTAssertEqual(OfflineLexicon.words(language: .russian).count, 30_000)
        XCTAssertGreaterThan(OfflineLexicon.words(language: .ukrainian).count, 25_000)
        for language in KeyboardLanguage.allCases {
            let words = OfflineLexicon.words(language: language)
            XCTAssertEqual(Set(words).count, words.count)
            XCTAssertTrue(words.allSatisfy { (2...24).contains($0.count) })
        }
    }
    func testConversationalWordsAndLanguageSpecificLettersArePresent() {
        for word in ["hello", "thanks", "keyboard", "tomorrow"] { XCTAssertTrue(OfflineLexicon.contains(word, language: .english), word) }
        for word in ["привет", "как", "спасибо", "сегодня"] { XCTAssertTrue(OfflineLexicon.contains(word, language: .russian), word) }
        for word in ["привіт", "як", "дякую", "сьогодні"] { XCTAssertTrue(OfflineLexicon.contains(word, language: .ukrainian), word) }
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
}
