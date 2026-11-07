import XCTest
@testable import KeyboardCore

final class EmojiCatalogTests: XCTestCase {
    func testBundledCatalogContainsUnicodeEmojiAndComponentsInDisplayOrder() {
        let catalog = EmojiCatalog.bundled()
        XCTAssertEqual(catalog.unicodeVersion, "18.0")
        XCTAssertEqual(catalog.count, 3972)
        XCTAssertEqual(catalog.sections.map(\.category), EmojiCategory.allCases)
        XCTAssertEqual(Set(catalog.sections.flatMap(\.entries).map(\.emoji)).count, catalog.count)
        XCTAssertTrue(catalog.sections.allSatisfy { !$0.entries.isEmpty })
    }

    func testCatalogIncludesJoinedFamilySkinToneFlagsAndNewestEmoji() {
        let entries = Set(EmojiCatalog.bundled().sections.flatMap(\.entries).map(\.emoji))
        for value in ["👨‍👩‍👧‍👦", "👩🏽‍💻", "🏳️‍🌈", "🇺🇦", "🫩", "🫆"] {
            XCTAssertTrue(entries.contains(value), "Missing emoji sequence: \(value)")
        }
    }

    func testCategoryLabelsAndIconsAreDefinedForAllSections() {
        XCTAssertEqual(EmojiCategory.allCases.count, 10)
        XCTAssertTrue(EmojiCategory.allCases.allSatisfy { !$0.titleKey.isEmpty && !$0.symbolName.isEmpty })
        XCTAssertEqual(EmojiCategory.smileys.titleKey, "Смайлы и эмоции")
        XCTAssertEqual(EmojiCategory.flags.symbolName, "flag.fill")
        XCTAssertTrue(EmojiCatalog.bundled().sections.contains { $0.category == .components && $0.entries.count == 9 })
        for category in EmojiCategory.allCases {
            XCTAssertNotEqual(GlassTypeText.translate(category.titleKey, to: .english), category.titleKey)
            XCTAssertNotEqual(GlassTypeText.translate(category.titleKey, to: .ukrainian), category.titleKey)
        }
    }

    func testEmojiSearchMatchesAnnotationsLocalizedAliasesAndSequences() {
        let items = EmojiCatalog.bundled().sections.flatMap(\.entries)
        XCTAssertTrue(EmojiSearch.search("grinning face", in: items).contains { $0.emoji == "😀" })
        XCTAssertTrue(EmojiSearch.search("СЕРДЦЕ", in: items).contains { $0.emoji == "❤️" })
        XCTAssertTrue(EmojiSearch.search("кіт", in: items).contains { $0.emoji == "🐈" || $0.emoji == "🐈‍⬛" })
        XCTAssertTrue(EmojiSearch.search("🇺🇦", in: items).contains { $0.emoji == "🇺🇦" })
        XCTAssertTrue(EmojiSearch.search("   ", in: items).isEmpty)
        XCTAssertEqual(EmojiSearch.search("heart", in: items, limit: 5).count, 5)
    }

    func testSkinToneVariantsCollapseAndCanBecomePreferredDefault() {
        let items = [EmojiItem(emoji: "👍", name: "thumbs up"), EmojiItem(emoji: "👍🏻", name: "thumbs up light skin tone"),
                     EmojiItem(emoji: "👍🏽", name: "thumbs up medium skin tone")]
        XCTAssertEqual(EmojiVariants.collapsed(items).map(\.emoji), ["👍"])
        XCTAssertEqual(EmojiVariants.choices(for: "👍", among: items).map(\.emoji), ["👍", "👍🏻", "👍🏽"])
        XCTAssertEqual(EmojiVariants.collapsed(items, preferred: ["👍": "👍🏽"]).map(\.emoji), ["👍🏽"])
    }

    func testBundledPickerHasOneEntryPerBaseGlyphIncludingMixedHandshakeTones() {
        let items = EmojiCatalog.bundled().sections.flatMap(\.entries)
        let collapsed = EmojiVariants.collapsed(items)
        XCTAssertEqual(collapsed.count, Set(collapsed.map { EmojiVariants.base(of: $0.emoji) }).count)
        let handshakes = EmojiVariants.choices(for: "🤝", among: items)
        XCTAssertTrue(handshakes.contains {
            let scalars = Set($0.emoji.unicodeScalars.map(\.value))
            return scalars.contains(0x1FAF1) && scalars.contains(0x1FAF2)
        })
        XCTAssertEqual(EmojiVariants.collapsed(handshakes).count, 1)
    }
}
