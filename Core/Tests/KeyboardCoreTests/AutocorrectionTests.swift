import XCTest
@testable import KeyboardCore

final class AutocorrectionTests: XCTestCase {
    func testPersonalKnownWordsAreSuggestedAndLegacyDataStillDecodes() throws {
        var lexicon = PersonalLexicon(knownWords: ["GlassType", "glasses"])
        XCTAssertEqual(lexicon.completions(for: "gla"), ["GlassType", "glasses"])
        XCTAssertTrue(lexicon.containsKnownWord("GLASSTYPE"))
        lexicon.addKnownWord("GlassType")
        XCTAssertEqual(lexicon.knownWords, ["GlassType", "glasses"])
        let pipeline = AutocorrectionPipeline()
        let customWord = PersonalLexicon(knownWords: ["teh"])
        XCTAssertFalse(pipeline.needsDictionaryChecks(for: "teh", language: .english, personalLexicon: customWord))
        XCTAssertNil(pipeline.replacement(for: "teh", language: .english, personalLexicon: customWord, offlineCheck: nil))

        let legacy = Data(#"{"replacements":{"teh":"the"},"excludedWords":["foobar"]}"#.utf8)
        let decoded = try JSONDecoder().decode(PersonalLexicon.self, from: legacy)
        XCTAssertEqual(decoded.replacements["teh"], "the")
        XCTAssertEqual(decoded.knownWords, [])
    }

    private let engine = AutocorrectionEngine()
    private let pipeline = AutocorrectionPipeline()

    func testCorrectionPipelineHonorsPersonalReplacementAndExclusionFirst() {
        let lexicon = PersonalLexicon(replacements: ["helo": "hello"], excludedWords: ["teh"])
        XCTAssertFalse(pipeline.needsDictionaryChecks(for: "helo", language: .english, personalLexicon: lexicon))
        XCTAssertEqual(pipeline.replacement(for: "helo", language: .english, personalLexicon: lexicon, offlineCheck: nil), "hello")
        XCTAssertNil(pipeline.replacement(for: "teh", language: .english, personalLexicon: lexicon, offlineCheck: nil))
    }

    func testCorrectionPipelineUsesExplicitRulesWithoutDictionarySnapshot() {
        XCTAssertEqual(pipeline.replacement(for: "helo", language: .english, personalLexicon: PersonalLexicon(), offlineCheck: nil), "hello")
        XCTAssertFalse(pipeline.needsDictionaryChecks(for: "helo", language: .english, personalLexicon: PersonalLexicon()))
    }

    func testCorrectionPipelineCombinesOfflineCandidatesAndRespectsKnownWords() {
        let misspelled = OfflineLexicon.SpellingCheck(known: false, candidates: ["hello"],
                                                      rankedCandidates: [.init("hello", frequencyRank: 1)])
        XCTAssertEqual(pipeline.replacement(for: "hellp", language: .english, personalLexicon: PersonalLexicon(),
                                            offlineCheck: misspelled), "hello")
        let known = OfflineLexicon.SpellingCheck(known: true, candidates: [], rankedCandidates: [])
        XCTAssertNil(pipeline.replacement(for: "hello", language: .english, personalLexicon: PersonalLexicon(),
                                          offlineCheck: known, systemCandidates: ["hell"]))
    }
    func testRankedCorrectionAcceptsMergedDictionariesWithMoreThanEightGuesses() {
        let guesses = Array(repeating: AutocorrectionEngine.Candidate("unrelated", frequencyRank: 1), count: 12)
            + [.init("keyboard", frequencyRank: 8791)]
        XCTAssertEqual(engine.rankedReplacement(for: "keybaord", language: .english, candidates: guesses), "keyboard")
    }
    func testFrequencyCanResolveDominantCandidateButNotNearTies() {
        XCTAssertEqual(engine.rankedReplacement(for: "hellp", language: .english, candidates: [
            .init("hello", frequencyRank: 10), .init("help", frequencyRank: 5000), .init("hell", frequencyRank: 8000)
        ]), "hello")
        XCTAssertNil(engine.rankedReplacement(for: "hellp", language: .english, candidates: [
            .init("hello", frequencyRank: 10), .init("help", frequencyRank: 10)
        ]))
    }
    func testLocalLanguageProfileCanRerankAnOtherwiseDominantCorrection() {
        let candidates = [AutocorrectionEngine.Candidate("help", frequencyRank: 1),
                          AutocorrectionEngine.Candidate("hello", frequencyRank: 10_000)]
        XCTAssertEqual(engine.rankedReplacement(for: "hellp", language: .english, candidates: candidates), "help")

        var model = PersonalNGramModel()
        for _ in 0..<8 { model.observe(context: "say", nextWord: "hello", language: .english) }
        XCTAssertEqual(engine.rankedReplacement(for: "hellp", language: .english, candidates: candidates,
                                                 languageModel: model, previousContext: "say"), "hello")
        let russianCandidates = [AutocorrectionEngine.Candidate("миром", frequencyRank: 1),
                                 AutocorrectionEngine.Candidate("мирой", frequencyRank: 10_000)]
        XCTAssertEqual(engine.rankedReplacement(for: "мирок", language: .russian, candidates: russianCandidates), "миром")
        XCTAssertEqual(engine.rankedReplacement(for: "мирок", language: .russian, candidates: russianCandidates,
                                                 languageModel: model, previousContext: "say"), "миром")
    }
    func testRankedCorrectionUsesActualOfflineCorporaForAllLanguages() {
        for (typo, expected, language) in [("keybaord", "keyboard", KeyboardLanguage.english),
                                           ("клавиатруа", "клавиатура", .russian), ("клавіатруа", "клавіатура", .ukrainian)] {
            _ = OfflineLexicon.words(language: language)
            let check = OfflineLexicon.preparedCheck(typo, language: language)!
            XCTAssertFalse(check.known)
            XCTAssertEqual(engine.rankedReplacement(for: typo, language: language, candidates: check.rankedCandidates), expected)
        }
    }
    func testRankedCorrectionProtectsKnownWordsAndIdentifiers() {
        let candidates = [AutocorrectionEngine.Candidate("hello", frequencyRank: 1)]
        XCTAssertNil(engine.rankedReplacement(for: "hellp", language: .english, candidates: candidates, isKnownWord: true))
        for value in ["HELLP", "HeLlP", "hellp1", "user@hellp", "hxxlo"] {
            XCTAssertNil(engine.rankedReplacement(for: value, language: .english, candidates: candidates))
        }
        XCTAssertEqual(engine.rankedReplacement(for: "Keybaord", language: .english, candidates: [.init("keyboard", frequencyRank: 100)]), "Keyboard")
    }
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
