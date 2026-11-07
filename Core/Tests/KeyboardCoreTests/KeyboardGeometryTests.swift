import Foundation
import CoreGraphics
import XCTest
@testable import KeyboardCore

final class KeyboardGeometryTests: XCTestCase {
    func testCustomRowsUseModeSwitchAndRetainBackspace() {
        let customRows = [["🙂", "😀"], ["🐶", "🐱"], ["👍", "❤️"]]
        let geometry = KeyboardGeometry.make(bounds: CGRect(x: 0, y: 0, width: 390, height: 260),
                                             language: .english, customRows: customRows,
                                             thirdRowUsesModeSwitch: true)
        let thirdRow = geometry.keys.filter { $0.row == 2 }
        XCTAssertEqual(thirdRow.first?.role, .modeSwitch)
        XCTAssertEqual(thirdRow.last?.role, .backspace)
        XCTAssertEqual(thirdRow.compactMap { $0.role.character }.count, customRows[2].count)
        XCTAssertTrue(thirdRow.compactMap { $0.role.character }.contains("❤️"))
    }

    func testMalformedCustomRowsReturnEmptyGeometryWithoutBreakingRegularLayouts() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 260)
        XCTAssertTrue(KeyboardGeometry.make(bounds: bounds, language: .russian, customRows: [["x"]]).keys.isEmpty)
        XCTAssertFalse(KeyboardGeometry.make(bounds: bounds, language: .russian).keys.isEmpty)
    }
    private let sizes: [CGSize] = [CGSize(width: 312, height: 220), CGSize(width: 367, height: 225),
        CGSize(width: 385, height: 225), CGSize(width: 393, height: 229.7), CGSize(width: 422, height: 240), CGSize(width: 732, height: 155),
        CGSize(width: 734, height: 155), CGSize(width: 750, height: 155), CGSize(width: 844, height: 165)]
    func testAllLayoutsAndSizesKeepCapsInsideTheirSlots() {
        for size in sizes {
            for language in KeyboardLanguage.allCases {
                let pages: [SymbolPage?] = [nil, .numbers, .extended]
                for page in pages {
                    for system in [true, false] {
                        let model = KeyboardGeometry.make(bounds: CGRect(origin: .zero, size: size), language: language, symbolPage: page, needsSystemKey: system)
                        XCTAssertFalse(model.keys.isEmpty)
                        XCTAssertEqual(Set(model.keys.map(\.index)).count, model.keys.count)
                        for key in model.keys {
                            XCTAssertTrue(model.bounds.insetBy(dx: -0.001, dy: -0.001).contains(key.slotFrame))
                            XCTAssertTrue(key.slotFrame.contains(key.visualFrame))
                            XCTAssertGreaterThan(key.visualFrame.width, 15)
                            XCTAssertLessThan(key.visualFrame.width, key.slotFrame.width)
                            XCTAssertEqual(model.cellIndex(at: key.center), key.index)
                        }
                    }
                }
            }
        }
    }
    func testAllRowsFillSameHorizontalSpanAndKeepEqualCapsWithinEachAlphabetRow() {
        for size in sizes {
            for language in KeyboardLanguage.allCases {
                for page in [SymbolPage.numbers, .extended] {
                    let layout = KeyboardGeometry.make(bounds: CGRect(origin: CGPoint(x: 5, y: 7), size: size),
                                                       language: language, symbolPage: page)
                    for row in 0..<4 {
                        let keys = layout.keys.filter { $0.row == row }
                        XCTAssertEqual(keys.first!.slotFrame.minX, CGFloat(9), accuracy: 0.001)
                        XCTAssertEqual(keys.last!.slotFrame.maxX, size.width + 1, accuracy: 0.001)
                    }
                }
                let layout = KeyboardGeometry.make(bounds: CGRect(x: 5, y: 7, width: size.width, height: size.height), language: language)
                for row in 0..<4 {
                    let keys = layout.keys.filter { $0.row == row }
                    XCTAssertEqual(keys.first!.slotFrame.minX, CGFloat(9), accuracy: 0.001)
                    XCTAssertEqual(keys.last!.slotFrame.maxX, size.width + 1, accuracy: 0.001)
                }
                for row in 0..<2 {
                    let keys = layout.keys.filter { $0.row == row }
                    XCTAssertTrue(keys.dropFirst().allSatisfy { abs($0.slotFrame.width - keys[0].slotFrame.width) < 0.001 })
                }
            }
        }
    }
    func testGapsMarginsAndOuterEdgesHaveOneOwner() {
        let layout = KeyboardGeometry.make(bounds: CGRect(x: 0, y: 0, width: 320, height: 220), language: .english)
        for key in layout.keys {
            let p = CGPoint(x: key.touchFrame.midX, y: key.touchFrame.midY)
            XCTAssertNotNil(layout.cellIndex(at: p))
            XCTAssertNotNil(layout.cellIndex(at: CGPoint(x: key.touchFrame.minX, y: key.touchFrame.minY)))
        }
        for y in stride(from: CGFloat(0), through: 220, by: 2.5) {
            for x in stride(from: CGFloat(0), through: 320, by: 2.5) { XCTAssertNotNil(layout.cellIndex(at: CGPoint(x: x, y: y))) }
        }
        XCTAssertNotNil(layout.cellIndex(at: CGPoint(x: 320, y: 220)))
        XCTAssertNil(layout.cellIndex(at: CGPoint(x: -0.001, y: 30)))
        XCTAssertNil(layout.cellIndex(at: CGPoint(x: 320.001, y: 30)))
        XCTAssertNil(layout.cellIndex(at: CGPoint(x: 30, y: 220.001)))
    }
    func testSharedCellBoundaryUsesRightOrLowerCell() {
        let layout = KeyboardGeometry.make(bounds: CGRect(x: 0, y: 0, width: 390, height: 220), language: .english)
        let first = layout.keys[0], next = layout.keys[1]
        XCTAssertEqual(layout.cellIndex(at: CGPoint(x: first.touchFrame.maxX, y: first.center.y)), next.index)
        let point = CGPoint(x: first.center.x, y: layout.pitch.height)
        XCTAssertEqual(layout.keys[layout.cellIndex(at: point)!].row, 1)
    }
    func testInvalidBoundsAreRejectedAndVisualStyleDoesNotAffectCells() {
        XCTAssertTrue(KeyboardGeometry.make(bounds: CGRect(x: 0, y: 0, width: CGFloat.nan, height: 220), language: .english).keys.isEmpty)
        XCTAssertTrue(KeyboardGeometry.make(bounds: .zero, language: .english).keys.isEmpty)
        let compact = KeyboardGeometry.make(bounds: CGRect(x: 0, y: 0, width: 390, height: 220), language: .russian)
        let large = KeyboardGeometry.make(bounds: compact.bounds, language: .russian, compact: false)
        XCTAssertEqual(compact.keys.map(\.touchFrame), large.keys.map(\.touchFrame))
        XCTAssertEqual(compact.keys.map(\.center), large.keys.map(\.center))
    }
    func testVisualWidthSliderNeverChangesTouchGeometryOrCreatesOverlaps() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 220)
        let base = KeyboardGeometry.make(bounds: bounds, language: .english)
        let narrow = KeyboardGeometry.make(bounds: bounds, language: .english, visualWidthScale: 0.84)
        let wide = KeyboardGeometry.make(bounds: bounds, language: .english, visualWidthScale: 1.12)
        XCTAssertEqual(base.keys.map(\.touchFrame), narrow.keys.map(\.touchFrame))
        XCTAssertEqual(base.keys.map(\.touchFrame), wide.keys.map(\.touchFrame))
        XCTAssertTrue(zip(narrow.keys, base.keys).allSatisfy { $0.0.visualFrame.width < $0.1.visualFrame.width })
        XCTAssertTrue(zip(wide.keys, base.keys).allSatisfy { $0.0.visualFrame.width >= $0.1.visualFrame.width })
        for model in [narrow, wide] {
            for row in 0..<4 {
                let keys = model.keys.filter { $0.row == row }
                for pair in zip(keys, keys.dropFirst()) {
                    XCTAssertLessThanOrEqual(pair.0.visualFrame.maxX, pair.1.visualFrame.minX + 0.001)
                }
            }
        }
    }
    func testKeyboardHeightSliderStaysInsideSafeRangeInBothOrientations() {
        for base in [CGFloat(188), CGFloat(254)] {
            let minimum = KeyboardSizing.height(base: base * 1.05, scale: 0.92, hasToolbar: false, bottomInset: 0)
            let defaultHeight = KeyboardSizing.height(base: base * 1.05, scale: 1, hasToolbar: false, bottomInset: 0)
            let maximum = KeyboardSizing.height(base: base * 1.05, scale: 1.10, hasToolbar: true, bottomInset: 0)
            XCTAssertGreaterThanOrEqual(minimum, 132)
            XCTAssertLessThan(minimum, defaultHeight)
            XCTAssertLessThan(defaultHeight, maximum)
        }
        XCTAssertEqual(KeyboardSizing.heightScale(.infinity), 1)
        XCTAssertEqual(KeyboardSizing.visualWidthScale(.nan), 1)
    }
    func testFractionalDimensionsUseCanonicalRowAndColumnBoundaries() {
        // Includes the actual +5% portrait geometry that exposes division drift.
        let heights: [CGFloat] = [229.7, 224.7, 234.7275, 185.3]
        for height in heights {
            for origin in [CGPoint.zero, CGPoint(x: 1.1, y: 2.2)] {
                for language in KeyboardLanguage.allCases {
                    let geometry = KeyboardGeometry.make(bounds: CGRect(x: origin.x, y: origin.y, width: 393.3333, height: height), language: language)
                    for key in geometry.keys {
                        let point = CGPoint(x: key.touchFrame.minX, y: key.center.y)
                        XCTAssertEqual(geometry.cellIndex(at: point), key.index)
                    }
                    for row in 1...3 {
                        let boundary = geometry.keys.first { $0.row == row }!.touchFrame.minY
                        let point = CGPoint(x: geometry.bounds.midX, y: boundary)
                        XCTAssertEqual(geometry.keys[geometry.cellIndex(at: point)!].row, row)
                        XCTAssertEqual(geometry.keys[geometry.cellIndex(at: CGPoint(x: point.x, y: boundary - 0.000001))!].row, row - 1)
                    }
                    let point = CGPoint(x: geometry.bounds.midX, y: geometry.bounds.minY + 3 * geometry.pitch.height)
                    let result = TouchRecognizer(geometry: geometry).resolve(point)!
                    XCTAssertEqual(geometry.keys[result.first.keyIndex].role, .space)
                }
            }
        }
    }

}
