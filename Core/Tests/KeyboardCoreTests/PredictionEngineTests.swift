import XCTest
@testable import KeyboardCore

final class PredictionEngineTests: XCTestCase {
    func testPredictionCombinesBundledAndPersonalPrefixCandidates() {
        _ = OfflineLexicon.words(language: .english)
        var lexicon = PersonalLexicon(); lexicon.addKnownWord("heythere")
        let result = PredictionEngine().predict(context: "say he", language: .english,
                                                personalLexicon: lexicon)
        XCTAssertEqual(result.prefix, "he")
        XCTAssertEqual(result.words.first, "heythere")
        XCTAssertEqual(result.words.count, 3)
        let generated = CandidateGenerator().candidates(prefix: "he", language: .english,
                                                         personalLexicon: lexicon, limit: 18)
        XCTAssertTrue(generated.contains("heythere"))
        XCTAssertTrue(generated.contains("hello"))
    }

    func testNextWordPredictionLearnsOnlyAggregatePerLanguageTransitions() throws {
        var model = PersonalNGramModel()
        model.observe(context: "we really", nextWord: "hello", language: .english)
        model.observe(context: "we really", nextWord: "hello", language: .english)
        model.observe(context: "we really", nextWord: "help", language: .english)
        let predictions = PredictionEngine().predict(context: "we really ", language: .english, model: model)
        XCTAssertEqual(predictions.words.first, "hello")
        XCTAssertFalse(PredictionEngine().predict(context: "we really ", language: .russian, model: model).words.contains("hello"))

        let encoded = try JSONEncoder().encode(model)
        let stored = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(stored.contains("we"))
        XCTAssertFalse(stored.contains("really"))
        XCTAssertTrue(stored.contains("hello"))
        XCTAssertLessThanOrEqual(model.contextCount, 2)
    }

    func testCurrentWordRankingUsesContextCountsWithoutChangingGeneratorFallback() {
        _ = OfflineLexicon.words(language: .english)
        var model = PersonalNGramModel()
        for _ in 0..<5 { model.observe(context: "say", nextWord: "hello", language: .english) }
        model.observe(context: "say", nextWord: "help", language: .english)
        let result = PredictionEngine().predict(context: "say he", language: .english, model: model)
        XCTAssertEqual(result.words.first, "hello")
        let fallback = PredictionEngine().predict(context: "say he", language: .english)
        XCTAssertEqual(fallback.words.first, "here")
    }

    func testNextWordAndProfanitySwitchesAreIndependentAndSafe() {
        var model = PersonalNGramModel()
        model.observe(context: "this is", nextWord: "hello", language: .english)
        XCTAssertTrue(PredictionEngine().predict(context: "this is ", language: .english, model: model,
                                                   nextWordPrediction: false).words.isEmpty)
        model.observe(context: "this is", nextWord: "fuck", language: .english)
        XCTAssertFalse(PredictionEngine().predict(context: "this is ", language: .english, model: model).words.contains("fuck"))
        XCTAssertTrue(PredictionEngine().predict(context: "this is ", language: .english, model: model,
                                                  includeProfanity: true).words.contains("fuck"))
    }

    func testModelIsBoundedAndSanitized() {
        var model = PersonalNGramModel()
        func letters(_ value: Int) -> String {
            var rest = value, result = ""
            repeat { result.append(Character(UnicodeScalar(97 + rest % 26)!)); rest /= 26 } while rest > 0
            return String(result.reversed())
        }
        for index in 0..<200 {
            model.observe(context: "context \(letters(index))", nextWord: letters(index + 1_000), language: .english)
        }
        XCTAssertLessThanOrEqual(model.sanitized().contextCount, 128)
        XCTAssertLessThanOrEqual(model.contextCount, 128)
    }

    func testGlideAddsSpaceAfterClosingPunctuationButNotAfterOpeningQuote() {
        for punctuation in [".", ",", "!", "?", ":", ";", "…", ")", "—", "/"] {
            XCTAssertEqual(GlideWordSpacing.leadingSpace(after: "Hello" + punctuation), " ")
        }
        XCTAssertEqual(GlideWordSpacing.leadingSpace(after: "Hello"), " ")
        XCTAssertEqual(GlideWordSpacing.leadingSpace(after: "Hello "), "")
        XCTAssertEqual(GlideWordSpacing.leadingSpace(after: "“"), "")
        XCTAssertEqual(GlideWordSpacing.leadingSpace(after: nil), "")
    }

    func testLearnsPredictionsAtAnEmptyContext() {
        var model = PersonalNGramModel()
        model.observe(context: "", nextWord: "hello", language: .english)
        XCTAssertEqual(model.nextWords(after: "", language: .english), ["hello"])
    }
}
