import Foundation
import XCTest
@testable import KeyboardCore

final class TypingConveniencesTests: XCTestCase {
    func testLetterAfterClosingPunctuationGetsOneSpace() {
        for mark in [".", ",", "!", "?", ":", ";", "…", ")", "]", "}", "»", "”", "%"] {
            XCTAssertEqual(PunctuationSpacing.prefixBeforeLetter(after: "Привет" + mark), " ", mark)
        }
        XCTAssertEqual(PunctuationSpacing.prefixBeforeLetter(after: "Hello. "), "")
        XCTAssertEqual(PunctuationSpacing.prefixBeforeLetter(after: nil), "")
    }
    func testLetterSpacingPreservesOpenersAndWordJoiners() {
        for ending in ["(", "[", "{", "«", "“", "-", "—", "'", "’", "/", ""] {
            XCTAssertEqual(PunctuationSpacing.prefixBeforeLetter(after: ending), "", ending)
        }
        XCTAssertEqual(PunctuationSpacing.prefixBeforeLetter(after: "example.com"), "")
        XCTAssertEqual(PunctuationSpacing.prefixBeforeLetter(after: "user@example.com"), "")
        XCTAssertEqual(PunctuationSpacing.prefixBeforeLetter(after: "https://example.com."), "")
    }
    func testDoubleSpaceAfterWordsInAllLanguages() {
        for text in ["Hello ", "Привет ", "Привіт ", "I ", "«привет ", "don’t ", "п'ять "] {
            XCTAssertEqual(SmartDoubleSpace.replacement(contextBeforeInput: text, elapsedSincePreviousSpace: 0.2), ". ", text)
            XCTAssertEqual(SmartDoubleSpace.replacement(contextBeforeInput: text, elapsedSincePreviousSpace: 0.3), ". ", text)
        }
        XCTAssertEqual(SmartDoubleSpace.maximumInterval, 0.3, accuracy: 0.000_001)
    }
    func testDoubleSpaceSkipsNumbersSignsAndAddresses() {
        for text in ["123 ", "1.5 ", "hello! ", "name@example.com ", "https://example.com ", "example.com ", "user123 ", "hello  ", " ", ""] {
            XCTAssertNil(SmartDoubleSpace.replacement(contextBeforeInput: text, elapsedSincePreviousSpace: 0.2), text)
        }
    }
    func testDoubleSpaceOnlyWithinQuickRepeatInterval() {
        XCTAssertNil(SmartDoubleSpace.replacement(contextBeforeInput: "word ", elapsedSincePreviousSpace: 0.300_001))
        XCTAssertNil(SmartDoubleSpace.replacement(contextBeforeInput: "word ", elapsedSincePreviousSpace: 1))
        XCTAssertNil(SmartDoubleSpace.replacement(contextBeforeInput: "word ", elapsedSincePreviousSpace: -0.1))
        XCTAssertNil(SmartDoubleSpace.replacement(contextBeforeInput: "word ", elapsedSincePreviousSpace: .infinity))
        XCTAssertNil(SmartDoubleSpace.replacement(contextBeforeInput: "word", elapsedSincePreviousSpace: 0.1))
        let period = SmartDoubleSpace.replacement(contextBeforeInput: "hello ", elapsedSincePreviousSpace: 0.2)
        XCTAssertEqual(period, ". ")
        var state = InputState()
        _ = state.inserted("a")
        state.synchronize(context: "hell" + (period ?? ""), autoCapitalization: true)
        XCTAssertEqual(state.shift, .once)
    }
    func testWordSwipeDeletesWordAndTrailingSpaces() throws {
        let plan = try XCTUnwrap(WordDeletionPlan.make(contextBeforeInput: "say привет  "))
        XCTAssertEqual(plan.deletedText, "привет  ")
        XCTAssertEqual(plan.characterCount, 8)
    }
    func testWordSwipePreservesUnicodeGraphemes() throws {
        let emoji = "👨‍👩‍👧‍👦"
        let plan = try XCTUnwrap(WordDeletionPlan.make(contextBeforeInput: "family " + emoji))
        XCTAssertEqual(plan.deletedText, emoji)
        let accent = try XCTUnwrap(WordDeletionPlan.make(contextBeforeInput: "say cafe\u{301}"))
        XCTAssertEqual(accent.characterCount, 4)
    }
    func testWordSwipeIncludesAttachedPunctuationAndApostrophe() throws {
        XCTAssertEqual(try XCTUnwrap(WordDeletionPlan.make(contextBeforeInput: "say hello! ")).deletedText, "hello! ")
        XCTAssertEqual(try XCTUnwrap(WordDeletionPlan.make(contextBeforeInput: "це п'ять")).deletedText, "п'ять")
    }
    func testWordSwipeDoesNotCrossNewlineOrUnknownContextEdge() throws {
        XCTAssertNil(WordDeletionPlan.make(contextBeforeInput: "wholeword"))
        XCTAssertEqual(try XCTUnwrap(WordDeletionPlan.make(contextBeforeInput: "wholeword", contextIsComplete: true)).deletedText, "wholeword")
        XCTAssertNil(WordDeletionPlan.make(contextBeforeInput: "hello\n"))
        XCTAssertEqual(try XCTUnwrap(WordDeletionPlan.make(contextBeforeInput: "hello\n  ")).deletedText, "  ")
        XCTAssertEqual(try XCTUnwrap(WordDeletionPlan.make(contextBeforeInput: "hello\nworld")).deletedText, "world")
    }
    func testWordSwipeRejectsOverlongIncompleteToken() {
        XCTAssertNil(WordDeletionPlan.make(contextBeforeInput: " " + String(repeating: "a", count: 200)))
        XCTAssertNil(WordDeletionPlan.make(contextBeforeInput: "say word", maximumCharacters: 0))
    }
    func testDeletionUndoRequiresSameDocumentCursorAndSelection() {
        let undo = TextDeletionUndo(deletedText: "hello ", before: "say ", after: "tail", document: "A")
        XCTAssertEqual(undo.deletedText, "hello ")
        XCTAssertTrue(undo.matches(before: "say ", after: "tail", document: "A", hasSelection: false))
        XCTAssertFalse(undo.matches(before: "say ", after: "tail", document: "B", hasSelection: false))
        XCTAssertFalse(undo.matches(before: "say ", after: "tail", document: "A", hasSelection: true))
        XCTAssertFalse(undo.matches(before: "say x", after: "tail", document: "A", hasSelection: false))
        XCTAssertFalse(undo.matches(before: nil, after: "tail", document: "A", hasSelection: false))
        XCTAssertFalse(undo.matches(before: "say ", after: "changed", document: "A", hasSelection: false))
    }
    func testSentenceCapitalizationAtStartNewlinesAndSentenceEnd() {
        for text in ["", "   ", "hello\n", "hello\n  ", "Привет. ", "Hello!", "Hello? ", "Hello... ", "Привіт… ", "Hello.\" ", "Hello!] ", "Уже 2026. ", "Версия 1.2. ",
                     String(repeating: "word ", count: 4_000) + ". "] {
            XCTAssertTrue(SentenceCapitalization.shouldCapitalize(contextBeforeInput: text), text)
        }
    }
    func testSentenceCapitalizationAvoidsDomainsAndDecimals() {
        for text in ["hello", "hello ", "example.", "1.5 ", "version1.2", String(repeating: "a", count: 8_000)] {
            XCTAssertFalse(SentenceCapitalization.shouldCapitalize(contextBeforeInput: text), text)
        }
        XCTAssertFalse(SentenceCapitalization.shouldCapitalize(contextBeforeInput: nil))
        // Only the last four characters are visible, so a dotted token that
        // ends in ". " is treated as a sentence boundary.
        for text in ["example.com. ", "https://host. ", "name@example. "] {
            XCTAssertTrue(SentenceCapitalization.shouldCapitalize(contextBeforeInput: text), text)
        }
    }
}

final class PersonalLexiconTests: XCTestCase {
    func testExclusionsAreCaseInsensitiveAndWinOverPairs() {
        let lexicon = PersonalLexicon(replacements: ["helo": "hello"], excludedWords: ["HELO"]).sanitized()
        XCTAssertTrue(lexicon.excludes("Helo"))
        XCTAssertNil(lexicon.replacement(for: "helo"))
    }
    func testUserCaseIsPreservedAndPlainValuesFollowSentenceCase() {
        let lexicon = PersonalLexicon(replacements: ["айфон": "iPhone", "helo": "hello"]).sanitized()
        XCTAssertEqual(lexicon.replacement(for: "Айфон"), "iPhone")
        XCTAssertEqual(lexicon.replacement(for: "Helo"), "Hello")
        XCTAssertEqual(lexicon.replacement(for: "HELO"), "HELLO")
    }
    func testSanitizesWhitespaceInvalidEntriesAndDuplicates() {
        let lexicon = PersonalLexicon(replacements: [" HELO ": " hello ", "bad key": "value", "empty": "  ", "line": "a\nb"], excludedWords: [" Cat ", "CAT", "", "bad word"]).sanitized()
        XCTAssertEqual(lexicon.replacements, ["helo": "hello"])
        XCTAssertEqual(lexicon.excludedWords, ["cat"])
    }
    func testManualDictionaryRoundTripsThroughLocalJSON() throws {
        let original = PersonalLexicon(replacements: ["адрес": "Київ, Україна", "айфон": "iPhone"], excludedWords: ["Codex"]).sanitized()
        let restored = try JSONDecoder().decode(PersonalLexicon.self, from: JSONEncoder().encode(original)).sanitized()
        XCTAssertEqual(restored, original)
    }
    func testEntryBoundsPreventUnboundedDictionaryGrowth() {
        var pairs: [String: String] = [:]
        for index in 0..<250 { pairs["word\(index)"] = "replacement" }
        let lexicon = PersonalLexicon(replacements: pairs, excludedWords: (0..<500).map { "word\($0)" }).sanitized()
        XCTAssertLessThanOrEqual(lexicon.replacements.count, 200)
        XCTAssertLessThanOrEqual(lexicon.excludedWords.count, 400)
    }
    func testCanonicalUnicodeExclusions() {
        let lexicon = PersonalLexicon(excludedWords: ["cafe\u{301}"]).sanitized()
        XCTAssertTrue(lexicon.excludes("CAFÉ"))
    }
}
