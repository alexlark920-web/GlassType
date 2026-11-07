import Foundation
import XCTest
@testable import KeyboardCore

final class TouchAdaptationTests: XCTestCase {
    func testLearnsOnlyBoundedNumericBiasAfterEnoughSamples() {
        var stats = TouchOffsetStatistics()
        for _ in 0..<31 { stats.observe(x: 0.12, y: -0.08) }
        XCTAssertEqual(stats.offsetX, 0)
        for _ in 0..<100 { stats.observe(x: 0.12, y: -0.08) }
        XCTAssertEqual(stats.offsetX, 0.12, accuracy: 1e-8)
        XCTAssertEqual(stats.offsetY, -0.08, accuracy: 1e-8)
        for _ in 0..<5000 { stats.observe(x: 0.4, y: -0.4) }
        XCTAssertLessThanOrEqual(abs(stats.offsetX), 0.18)
        XCTAssertEqual(stats.count, 4096)
        XCTAssertTrue(stats.isValid)
    }
    func testRejectsOutliersAndNonfiniteSamples() {
        var stats = TouchOffsetStatistics()
        for value in [Double.nan, .infinity, -.infinity, 0.43, -0.43] { XCTAssertFalse(stats.observe(x: value, y: 0)) }
        XCTAssertEqual(stats.count, 0)
    }
    func testOrientationAndDisableAreIndependent() {
        var state = TouchAdaptationState()
        for _ in 0..<140 { state.portrait.observe(x: 0.1, y: 0.05) }
        XCTAssertEqual(state.configuration(landscape: false, enabled: true).offsetX, 0.1, accuracy: 1e-8)
        XCTAssertEqual(state.configuration(landscape: true, enabled: true).offsetX, 0)
        XCTAssertEqual(state.configuration(landscape: false, enabled: false).offsetX, 0)
        XCTAssertLessThan(state.configuration(landscape: false, enabled: true).sigmaX, 0.34)
        XCTAssertEqual(state.configuration(landscape: false, enabled: false).sigmaX, 0.34)
        XCTAssertEqual(state.portrait.count, 140)
        state = TouchAdaptationState()
        XCTAssertEqual(state.portrait.count, 0)
        XCTAssertEqual(state.landscape.count, 0)
    }

    func testTapSpreadLearnsBoundedProbabilityWidthWithoutStoringSamples() throws {
        var stable = TouchOffsetStatistics()
        for _ in 0..<192 { stable.observe(x: 0.08, y: -0.04) }
        XCTAssertEqual(stable.learnedSigmaX, 0.24, accuracy: 1e-8)

        var variable = TouchOffsetStatistics()
        for index in 0..<192 {
            let value = index.isMultiple(of: 2) ? -0.34 : 0.34
            variable.observe(x: value, y: value)
        }
        XCTAssertGreaterThan(variable.learnedSigmaX, stable.learnedSigmaX)
        XCTAssertLessThanOrEqual(variable.learnedSigmaX, 0.46)
        let data = try JSONEncoder().encode(variable)
        XCTAssertLessThan(data.count, 1024)
        let decoded = try JSONDecoder().decode(TouchOffsetStatistics.self, from: data)
        XCTAssertEqual(decoded, variable)
    }
    func testPersistenceHasNoTextOrRawHistoryAndRoundTrips() throws {
        var state = TouchAdaptationState()
        state.portrait.observe(x: 0.1, y: 0.05)
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(TouchAdaptationState.self, from: data)
        XCTAssertEqual(decoded, state)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["version", "portrait", "landscape"]))
        let fields = try XCTUnwrap(object["portrait"] as? [String: Any])
        XCTAssertEqual(Set(fields.keys), Set(["count", "meanX", "meanY", "varianceSumX", "varianceSumY"]))
        XCTAssertTrue(fields.values.allSatisfy { $0 is NSNumber })
        XCTAssertLessThan(data.count, 1024)
    }
    func testCorruptPersistedValuesAreNotUsed() throws {
        let json = "{\"version\":1,\"portrait\":{\"count\":-1,\"meanX\":99,\"meanY\":0,\"varianceSumX\":0,\"varianceSumY\":0},\"landscape\":{\"count\":0,\"meanX\":0,\"meanY\":0,\"varianceSumX\":0,\"varianceSumY\":0}}"
        let state = try JSONDecoder().decode(TouchAdaptationState.self, from: Data(json.utf8))
        XCTAssertFalse(state.isValid)
        XCTAssertEqual(state.configuration(landscape: false, enabled: true).offsetX, 0)
    }
}
