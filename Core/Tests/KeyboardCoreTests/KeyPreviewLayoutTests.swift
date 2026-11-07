import Foundation
import CoreGraphics
import XCTest
@testable import KeyboardCore

final class KeyPreviewLayoutTests: XCTestCase {
    func testFlagStaysInsideKeyboardAtBothEdgesAndOrientations() throws {
        for bounds in [CGRect(x: 0, y: 0, width: 393, height: 288), CGRect(x: 0, y: 0, width: 852, height: 188)] {
            for key in [CGRect(x: 4, y: 37, width: 32, height: 53),
                        CGRect(x: bounds.width - 36, y: 37, width: 32, height: 53),
                        CGRect(x: bounds.midX, y: 100, width: 36, height: 45)] {
                let layout = try XCTUnwrap(KeyPreviewLayout.make(keyFrame: key, availableBounds: bounds))
                XCTAssertTrue(bounds.contains(layout.frame))
                XCTAssertGreaterThan(layout.stemCenterX - layout.stemWidth / 2, 0)
                XCTAssertLessThan(layout.stemCenterX + layout.stemWidth / 2, layout.frame.width)
            }
        }
    }
    func testFirstRowWithoutPredictionStripDoesNotEscapeWindow() throws {
        let bounds = CGRect(x: 0, y: 0, width: 393, height: 222)
        let key = CGRect(x: 4, y: 5, width: 32, height: 53)
        let layout = try XCTUnwrap(KeyPreviewLayout.make(keyFrame: key, availableBounds: bounds))
        XCTAssertTrue(bounds.contains(layout.frame))
        XCTAssertGreaterThanOrEqual(layout.frame.height, 44)
    }
    func testNarrowKeyboardAndNonzeroOriginAreHandled() throws {
        let bounds = CGRect(x: 20, y: 10, width: 160, height: 150)
        let key = CGRect(x: 25, y: 70, width: 24, height: 40)
        let layout = try XCTUnwrap(KeyPreviewLayout.make(keyFrame: key, availableBounds: bounds))
        XCTAssertTrue(bounds.contains(layout.frame))
    }
    func testInvalidOrOffscreenGeometryIsIgnored() {
        let bounds = CGRect(x: 0, y: 0, width: 393, height: 254)
        XCTAssertNil(KeyPreviewLayout.make(keyFrame: .zero, availableBounds: bounds))
        XCTAssertNil(KeyPreviewLayout.make(keyFrame: CGRect(x: 1000, y: 0, width: 30, height: 50), availableBounds: bounds))
        XCTAssertNil(KeyPreviewLayout.make(keyFrame: CGRect(x: 4, y: 40, width: 30, height: 50), availableBounds: CGRect(x: 0, y: 0, width: 30, height: 254)))
    }
}
