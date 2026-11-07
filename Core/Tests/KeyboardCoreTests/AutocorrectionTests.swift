import XCTest
@testable import KeyboardCore

final class AutocorrectionTests: XCTestCase {
    private let engine = AutocorrectionEngine()
    func testCommonTyposInAllLanguages() {
        XCTAssertEqual(engine.replacement(for: "teh", language: .english), "the")
        XCTAssertEqual(engine.replacement(for: "helo", language: .english), "hello")
        XCTAssertEqual(engine.replacement(for: "првиет", language: .russian), "привет")
        XCTAssertEqual(engine.replacement(for: "спсибо", language: .russian), "спасибо")
        XCTAssertEqual(engine.replacement(for: "дякуб", language: .ukrainian), "дякую")
        XCTAssertEqual(engine.replacement(for: "сьогдні", language: .ukrainian), "сьогодні")
    }
    func testPreservesSentenceCapitalization() {
        XCTAssertEqual(engine.replacement(for: "Helo", language: .english), "Hello")
        XCTAssertEqual(engine.replacement(for: "Првиет", language: .russian), "Привет")
        XCTAssertEqual(engine.replacement(for: "Дякуб", language: .ukrainian), "Дякую")
    }
    func testValidWordReportedByDictionaryWins() {
        XCTAssertNil(engine.replacement(for: "teh", language: .english, isKnownWord: true))
        XCTAssertNil(engine.replacement(for: "form", language: .english, candidates: ["from"], isKnownWord: true))
    }
    func testUniqueSystemCandidateAndTransposition() {
        XCTAssertEqual(engine.replacement(for: "hlelo", language: .english, candidates: ["hello"]), "hello")
        XCTAssertEqual(engine.replacement(for: "worl", language: .english, candidates: ["world"]), "world")
    }
    func testAmbiguousGuessesLeaveOriginalAlone() {
        XCTAssertNil(engine.replacement(for: "hellp", language: .english, candidates: ["hello", "help"]))
        XCTAssertNil(engine.replacement(for: "hxxlo", language: .english, candidates: ["hello"]))
    }
    func testIgnoresAllCapsMixedCaseAndNonWords() {
        for word in ["HELO", "HeLo", "hello1", "he_lo", "", "hi", "👨‍👩‍👧‍👦", String(repeating: "a", count: 25)] {
            XCTAssertNil(engine.replacement(for: word, language: .english, candidates: ["hello"]))
        }
    }
    func testNoUnrequestedTransliteration() {
        XCTAssertNil(engine.replacement(for: "првиет", language: .english, candidates: ["привет"]))
        XCTAssertNil(engine.replacement(for: "првиет", language: .ukrainian))
        XCTAssertNil(engine.replacement(for: "helo", language: .russian, candidates: ["hello"]))
    }
    func testDeduplicatesSystemCandidates() {
        XCTAssertEqual(engine.replacement(for: "hlelo", language: .english, candidates: ["hello", "Hello", "hello"]), "hello")
    }
    func testLimitsGuessesAndRejectsPhraseCandidates() {
        let guesses = Array(repeating: "unrelated", count: 8) + ["hello"]
        XCTAssertNil(engine.replacement(for: "hlelo", language: .english, candidates: guesses))
        XCTAssertNil(engine.replacement(for: "worl", language: .english, candidates: ["world wide"]))
    }
    func testSingleEditOperationsAndBoundaries() {
        for (a, b) in [("worl", "world"), ("helllo", "hello"), ("hellp", "hello"), ("hlelo", "hello"), ("", "a"), ("a", "")] {
            XCTAssertTrue(AutocorrectionEngine.isSingleEdit(a, b), "\(a) → \(b)")
        }
        for (a, b) in [("hello", "hello"), ("hxxlo", "hello"), ("ab", "baaa"), ("abc", "cba"), ("", "")] {
            XCTAssertFalse(AutocorrectionEngine.isSingleEdit(a, b), "\(a) → \(b)")
        }
    }
    func testExtractsPlainWordAfterWhitespaceAndOpeningQuote() {
        XCTAssertEqual(AutocorrectionEngine.trailingPlainWord(in: "say helo"), "helo")
        XCTAssertEqual(AutocorrectionEngine.trailingPlainWord(in: "«Првиет"), "Првиет")
        XCTAssertEqual(AutocorrectionEngine.trailingPlainWord(in: "\n(првиет"), "првиет")
    }
    func testDoesNotTouchAddressesIdentifiersOrApostrophes() {
        for text in ["user@helo", "https://helo", "file.helo", "abc123helo", "#првиет", "don’t", "п'ять", "hello ", "hi", ""] {
            XCTAssertNil(AutocorrectionEngine.trailingPlainWord(in: text), text)
        }
    }
    func testUndoRequiresSameCursorDocumentAndSelection() {
        let undo = CorrectionUndo(original: "helo", replacement: "hello", delimiter: " ", before: "say hello ", after: "tail", document: "A")
        XCTAssertTrue(undo.matches(before: "say hello ", after: "tail", document: "A", hasSelection: false))
        XCTAssertFalse(undo.matches(before: "say hello ", after: "tail", document: "B", hasSelection: false))
        XCTAssertFalse(undo.matches(before: "say hello ", after: "tail", document: "A", hasSelection: true))
        XCTAssertFalse(undo.matches(before: "say hello", after: " tail", document: "A", hasSelection: false))
        XCTAssertFalse(undo.matches(before: "say hello ", after: "changed", document: "A", hasSelection: false))
        XCTAssertFalse(undo.matches(before: nil, after: "tail", document: "A", hasSelection: false))
    }
    func testUndoSupportsUnicodeAndUnavailableTrailingContext() {
        let undo = CorrectionUndo(original: "првиет", replacement: "привет", delimiter: ".", before: "👨‍👩‍👧‍👦 привет.", after: nil, document: "A")
        XCTAssertTrue(undo.matches(before: "👨‍👩‍👧‍👦 привет.", after: nil, document: "A", hasSelection: false))
        XCTAssertFalse(undo.matches(before: "👨‍👩‍👧‍👦 привет. ещё", after: nil, document: "A", hasSelection: false))
    }
}
