import XCTest
@testable import KeyboardCore

final class SymbolPageTests: XCTestCase {
    func testSwitchTitlesDescribeDestinationAndToggleBack() {
        XCTAssertEqual(SymbolPage.numbers.switchTitle, "#*=")
        XCTAssertEqual(SymbolPage.extended.switchTitle, "123")
        XCTAssertEqual(SymbolPage.numbers.next, .extended)
        XCTAssertEqual(SymbolPage.extended.next, .numbers)
        XCTAssertEqual(SymbolPage.numbers.next.next, .numbers)
    }
    func testBothPagesHaveThreeRowsAndNoEmptyKeys() {
        for page in SymbolPage.allCases {
            XCTAssertEqual(page.rows.count, 3)
            XCTAssertTrue(page.rows.flatMap { $0 }.allSatisfy { !$0.isEmpty })
            XCTAssertTrue(page.rows.allSatisfy { $0.count <= 12 })
        }
    }
    func testNumbersAndSecondPageOfferDifferentCharacters() {
        XCTAssertEqual(SymbolPage.numbers.rows[0].joined(), "1234567890")
        for symbol in ["[", "]", "{", "}", "\\", "÷"] {
            XCTAssertTrue(SymbolPage.extended.rows.flatMap { $0 }.contains(symbol))
        }
        for symbol in ["€", "₴", "₽"] { XCTAssertFalse(SymbolPage.extended.rows.flatMap { $0 }.contains(symbol)) }
    }
    func testPageStateDoesNotChangeLanguageOrShift() {
        var state = InputState(language: .ukrainian)
        let shift = state.shift
        state.symbols = true; state.symbolPage = state.symbolPage.next
        XCTAssertEqual(state.language, .ukrainian)
        XCTAssertEqual(state.shift, shift)
        XCTAssertTrue(state.symbols)
        XCTAssertEqual(state.symbolPage, .extended)
    }
    func testMathSymbolsKeepCaseWithoutConsumingLetterShift() {
        var state = InputState()
        state.symbols = true; state.symbolPage = .extended
        XCTAssertEqual(state.inserted("π"), "π")
        XCTAssertEqual(state.shift, .once)
        state.symbols = false
        XCTAssertEqual(state.inserted("a"), "A")
    }

}
