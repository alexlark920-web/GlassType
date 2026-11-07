import Foundation
import CoreGraphics
import XCTest
@testable import KeyboardCore

final class TouchRecognitionTests: XCTestCase {
    private func layout(_ language: KeyboardLanguage = .english, width: CGFloat = 385, height: CGFloat = 225) -> KeyboardGeometry {
        KeyboardGeometry.make(bounds: CGRect(x: 0, y: 0, width: width, height: height), language: language)
    }
    func testEveryKeyCenterAndCornerResolvesAtEverySize() {
        for language in KeyboardLanguage.allCases {
            for size in [CGSize(width: 312, height: 225), CGSize(width: 385, height: 225), CGSize(width: 750, height: 155)] {
                let geometry = layout(language, width: size.width, height: size.height), model = TouchRecognizer(geometry: layout(language, width: size.width, height: size.height))
                for key in geometry.keys { XCTAssertEqual(model.resolve(key.center)?.first.keyIndex, key.index) }
                for point in [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)] { XCTAssertNotNil(model.resolve(point)) }
            }
        }
    }
    func testBoundaryIsAmbiguousWithStableTieBreak() {
        let geometry = layout(), model = TouchRecognizer(geometry: layout())
        let left = geometry.keys[3], right = geometry.keys[4]
        let point = CGPoint(x: (left.center.x + right.center.x) / 2, y: left.center.y)
        let result = model.resolve(point)!
        XCTAssertEqual(result.first.keyIndex, left.index)
        XCTAssertEqual(result.second?.keyIndex, right.index)
        XCTAssertTrue(result.isAmbiguous)
        XCTAssertEqual(result.first.geometricProbability, result.second!.geometricProbability, accuracy: 1e-10)
        XCTAssertEqual(model.resolve(CGPoint(x: point.x - 0.001, y: point.y))?.first.keyIndex, left.index)
        XCTAssertEqual(model.resolve(CGPoint(x: point.x + 0.001, y: point.y))?.first.keyIndex, right.index)
    }
    func testVisualGapsHaveNoDeadZonesOrConflictingOwners() {
        let geometry = layout(.russian), model = TouchRecognizer(geometry: layout(.russian))
        for y in stride(from: CGFloat(0), through: geometry.bounds.height, by: 3) {
            for x in stride(from: CGFloat(0), through: geometry.bounds.width, by: 3) {
                let point = CGPoint(x: x, y: y)
                let result = model.resolve(point)!
                XCTAssertTrue(geometry.keys.indices.contains(result.first.keyIndex))
                XCTAssertGreaterThan(result.first.probability, 0)
                XCTAssertLessThanOrEqual(result.first.probability, 1.00000001)
                XCTAssertEqual(result.first.keyIndex, model.resolve(point)?.first.keyIndex)
            }
        }
    }
    func testCalibrationChangesRecognitionWithoutMovingAnyCaps() {
        let geometry = layout(), left = geometry.keys[2], right = geometry.keys[3]
        let point = CGPoint(x: (left.center.x + right.center.x) / 2 + geometry.pitch.width * 0.08, y: left.center.y)
        var model = TouchRecognizer(geometry: geometry)
        XCTAssertEqual(model.resolve(point)?.first.keyIndex, right.index)
        model.configuration.offsetX = 0.15
        XCTAssertEqual(model.resolve(point)?.first.keyIndex, left.index)
        XCTAssertEqual(model.geometry.keys.map(\.visualFrame), geometry.keys.map(\.visualFrame))
    }
    private struct Prior: CharacterLanguagePrior {
        func probability(of character: String, language: KeyboardLanguage, context: String) -> Double { character == "t" ? 1 : 0.001 }
    }
    func testLanguagePriorIsSeparateOptionalAndCannotStealFunctionKeys() {
        let geometry = layout(), r = geometry.keys[3], t = geometry.keys[4]
        let point = CGPoint(x: (r.center.x + t.center.x) / 2 - 0.05, y: r.center.y)
        var model = TouchRecognizer(geometry: geometry)
        let plain = model.resolve(point)!
        XCTAssertEqual(model.resolve(point, prior: Prior())?.first.keyIndex, plain.first.keyIndex)
        model.configuration.languageWeight = 0.3
        let result = model.resolve(point, prior: Prior(), context: "example")!
        XCTAssertEqual(result.first.keyIndex, t.index)
        XCTAssertLessThan(result.first.geometricProbability, plain.first.geometricProbability)
        let space = geometry.keys.first { $0.role == .space }!
        XCTAssertEqual(model.resolve(space.center, prior: Prior())?.first.keyIndex, space.index)
    }
    func testInvalidInputsAndConfigurationAreSafe() {
        var model = TouchRecognizer(geometry: layout())
        model.configuration.offsetX = .nan; model.configuration.offsetY = .infinity
        model.configuration.sigmaX = -1; model.configuration.sigmaY = .nan
        XCTAssertNotNil(model.resolve(CGPoint(x: 10, y: 10)))
        XCTAssertNil(model.resolve(CGPoint(x: CGFloat.nan, y: 0)))
        XCTAssertNil(model.resolve(CGPoint(x: -1, y: 0)))
        XCTAssertNil(model.resolve(CGPoint(x: 10, y: 226)))
    }
    func testDebugPolygonsMatchActualResolver() {
        var model = TouchRecognizer(geometry: layout(.ukrainian))
        model.configuration.offsetX = 0.12; model.configuration.offsetY = -0.08
        let zones = model.debugZones()
        XCTAssertFalse(zones.isEmpty)
        var area: CGFloat = 0
        for zone in zones where zone.polygon.count >= 3 {
            let points = zone.polygon
            let signedArea = zip(points, Array(points.dropFirst()) + [points[0]]).reduce(CGFloat(0)) { $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y } / 2
            guard abs(signedArea) > 0.0001 else { continue }
            area += abs(signedArea)
            let center = CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count), y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
            XCTAssertEqual(model.resolve(center)?.first.keyIndex, zone.keyIndex)
        }
        XCTAssertEqual(area, model.geometry.bounds.width * model.geometry.bounds.height, accuracy: 0.01)
    }
    func testRapidTypingWorkload() {
        let geometry = layout(.russian), model = TouchRecognizer(geometry: layout(.russian))
        var matched = 0
        for _ in 0..<250 {
            for key in geometry.keys { if model.resolve(key.center)?.first.keyIndex == key.index { matched += 1 } }
        }
        XCTAssertEqual(matched, geometry.keys.count * 250)
    }
}
