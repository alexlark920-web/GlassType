import XCTest
@testable import KeyboardCore

final class KeyboardTuningConfigTests: XCTestCase {
    func testDocumentedDefaults() {
        let tuning = KeyboardTuningConfig(
            spatialWeight: 0.65,
            frequencyWeight: 0.35,
            baseSigma: 34,
            edgeKeySigmaMultiplier: 1.25,
            beamWidth: 16,
            frameThrottleIntervalMs: 8,
            glideActivationThresholdPoints: 12,
            diagnosticsEnabled: false
        )
        XCTAssertEqual(tuning.spatialWeight, 0.65)
        XCTAssertEqual(tuning.frequencyWeight, 0.35)
        XCTAssertEqual(tuning.spatialWeight + tuning.frequencyWeight, 1, accuracy: 0.0001)
        XCTAssertEqual(tuning.baseSigma, 34)
        XCTAssertEqual(tuning.edgeKeySigmaMultiplier, 1.25)
        XCTAssertEqual(tuning.beamWidth, 16)
        XCTAssertEqual(tuning.frameThrottleIntervalMs, 8)
        XCTAssertEqual(tuning.frameThrottleInterval, 0.008, accuracy: 0.000_000_1)
        XCTAssertEqual(tuning.glideActivationThresholdPoints, 12)
        XCTAssertFalse(tuning.diagnosticsEnabled)
    }

    func testOuterColumnsUseTheWiderGaussian() {
        let tuning = KeyboardTuningConfig(diagnosticsEnabled: false)
        for key in ["q", "a", "z", "p", "l", "m", "Q"] {
            XCTAssertTrue(tuning.isEdgeColumn(key), key)
            XCTAssertEqual(tuning.sigma(for: key), tuning.baseSigma * tuning.edgeKeySigmaMultiplier, accuracy: 0.001)
        }
        XCTAssertFalse(tuning.isEdgeColumn("w"))
        XCTAssertEqual(tuning.sigma(for: "s"), tuning.baseSigma)
        XCTAssertTrue(tuning.isEdgeColumn("й"))
        XCTAssertTrue(tuning.isEdgeColumn("ю"))
    }

    func testBeamWidthAndTravelAreClamped() {
        let tuning = KeyboardTuningConfig(beamWidth: 1, frameThrottleIntervalMs: 0, glideActivationThresholdPoints: 1, diagnosticsEnabled: false)
        XCTAssertEqual(tuning.beamWidth, 4)
        XCTAssertEqual(tuning.frameThrottleIntervalMs, 1)
        XCTAssertEqual(tuning.glideActivationThresholdPoints, 7)
    }

    func testReleaseDiagnosticsSnapshotStaysEmptyWhenRecordingIsDisabled() {
        let diagnostics = KeyboardFrameDiagnostics.shared
        diagnostics.reset()
        let before = diagnostics.snapshot()
        diagnostics.record(nanoseconds: 2_000_000)
        let after = diagnostics.snapshot()
        #if DEBUG
        XCTAssertEqual(after.sampleCount, before.sampleCount + 1)
        XCTAssertGreaterThan(after.averageMilliseconds, 0)
        #else
        XCTAssertEqual(after.sampleCount, 0)
        XCTAssertEqual(after.averageMilliseconds, 0)
        XCTAssertNil(after.physicalFootprintBytes)
        #endif
    }
}
