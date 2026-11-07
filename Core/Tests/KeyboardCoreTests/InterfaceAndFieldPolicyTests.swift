import XCTest
@testable import KeyboardCore

final class InterfaceAndFieldPolicyTests: XCTestCase {
    func testAllInterfaceLanguagesHaveStableNativeLabels() {
        XCTAssertEqual(InterfaceLanguage.allCases.count, 3)
        XCTAssertEqual(InterfaceLanguage.russian.title, "Русский")
        XCTAssertEqual(InterfaceLanguage.english.title, "English")
        XCTAssertEqual(InterfaceLanguage.ukrainian.title, "Українська")
        XCTAssertEqual(GlassTypeText.translate("Автозамена", to: .english), "Auto-correction")
        XCTAssertEqual(GlassTypeText.translate("Автозамена", to: .ukrainian), "Автозаміна")
    }

    func testUnknownCopyFallsBackAndRussianRemainsSourceCopy() {
        XCTAssertEqual(GlassTypeText.translate("Новая подпись", to: .english), "Новая подпись")
        XCTAssertEqual(GlassTypeText.translate("Автозамена", to: .russian), "Автозамена")
    }

    func testAutomationOnlyRunsInOrdinaryNonSecureFields() {
        XCTAssertTrue(TextAutomationPolicy.allowsCorrection(in: .standard, isSecure: false))
        XCTAssertFalse(TextAutomationPolicy.allowsCorrection(in: .standard, isSecure: true))
        for kind in KeyboardInputFieldKind.allCases where kind != .standard {
            XCTAssertFalse(TextAutomationPolicy.allowsCorrection(in: kind, isSecure: false), "\(kind)")
        }
    }
}
