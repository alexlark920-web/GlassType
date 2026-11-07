import XCTest
@testable import KeyboardCore

final class AlternateSymbolsTests: XCTestCase {
    func testTopRowDigitsForEveryLanguage() {
        let digits = (1...9).map(String.init) + ["0"]
        for language in KeyboardLanguage.allCases {
            for (key, digit) in zip(language.rows[0], digits) {
                XCTAssertEqual(language.holdAlternatives(for: key, symbolsEnabled: true).first, digit)
            }
        }
    }
    func testDisabledSymbolsPreserveLanguageVariants() {
        XCTAssertEqual(KeyboardLanguage.russian.holdAlternatives(for: "е", symbolsEnabled: false), ["ё"])
        XCTAssertEqual(KeyboardLanguage.ukrainian.holdAlternatives(for: "г", symbolsEnabled: false), ["ґ"])
        XCTAssertEqual(KeyboardLanguage.english.holdAlternatives(for: "e", symbolsEnabled: false), ["é", "è", "ë", "ê"])
        XCTAssertTrue(KeyboardLanguage.english.holdAlternatives(for: "q", symbolsEnabled: false).isEmpty)
    }
    func testSymbolsAndLanguageVariantsAreBothAvailable() {
        XCTAssertEqual(KeyboardLanguage.russian.holdAlternatives(for: "Е", symbolsEnabled: true), ["5", "ё"])
        XCTAssertEqual(KeyboardLanguage.ukrainian.holdAlternatives(for: "Г", symbolsEnabled: true), ["7", "ґ"])
    }
    func testLocaleCurrency() {
        for (language, currency) in [(KeyboardLanguage.english, "$"), (.russian, "₽"), (.ukrainian, "₴")] {
            let key = language.rows[1][2]
            XCTAssertEqual(language.holdAlternatives(for: key, symbolsEnabled: true).first, currency)
        }
    }
    func testAllKeysHaveDistinctNonemptyHoldChoices() {
        for language in KeyboardLanguage.allCases {
            for key in language.rows.flatMap({ $0 }) {
                let choices = language.holdAlternatives(for: key, symbolsEnabled: true)
                XCTAssertFalse(choices.isEmpty)
                XCTAssertFalse(choices.contains(key))
                XCTAssertEqual(choices.count, Set(choices).count)
            }
        }
    }
    func testUnknownKeyAndPunctuationAreSafe() {
        for enabled in [true, false] {
            XCTAssertTrue(KeyboardLanguage.english.holdAlternatives(for: "🦊", symbolsEnabled: enabled).isEmpty)
            XCTAssertEqual(KeyboardLanguage.russian.holdAlternatives(for: ".", symbolsEnabled: enabled), [",", "?", "!", ":", ";", "…"])
        }
    }
}
