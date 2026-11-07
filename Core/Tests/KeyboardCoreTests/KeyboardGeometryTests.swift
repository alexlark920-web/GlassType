import Foundation
import CoreGraphics
import XCTest
@testable import KeyboardCore

final class KeyboardGeometryTests: XCTestCase {
    private let sizes: [CGSize] = [CGSize(width: 312, height: 220), CGSize(width: 367, height: 225),
        CGSize(width: 385, height: 225), CGSize(width: 422, height: 240), CGSize(width: 732, height: 155),
        CGSize(width: 750, height: 155), CGSize(width: 844, height: 165)]
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
    func testRowsUseSamePitchAndCorrectHalfKeyIndent() {
        for language in KeyboardLanguage.allCases {
            let layout = KeyboardGeometry.make(bounds: CGRect(x: 5, y: 7, width: 385, height: 220), language: language)
            let first = layout.keys.first { $0.row == 0 }!
            let second = layout.keys.first { $0.row == 1 }!
            XCTAssertEqual(second.slotFrame.minX - first.slotFrame.minX, layout.pitch.width / 2, accuracy: 0.001)
            XCTAssertEqual(first.slotFrame.width, second.slotFrame.width, accuracy: 0.001)
            let third = layout.keys.first { $0.row == 2 && $0.role.character != nil }!
            XCTAssertEqual(third.slotFrame.width, layout.pitch.width, accuracy: 0.001)
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
        XCTAssertTrue(KeyboardGeometry.make(bounds: CGRect(x: 0, y: 0, width: .nan, height: 220), language: .english).keys.isEmpty)
        XCTAssertTrue(KeyboardGeometry.make(bounds: .zero, language: .english).keys.isEmpty)
        let compact = KeyboardGeometry.make(bounds: CGRect(x: 0, y: 0, width: 390, height: 220), language: .russian)
        let large = KeyboardGeometry.make(bounds: compact.bounds, language: .russian, compact: false)
        XCTAssertEqual(compact.keys.map(\.touchFrame), large.keys.map(\.touchFrame))
        XCTAssertEqual(compact.keys.map(\.center), large.keys.map(\.center))
    }
}
