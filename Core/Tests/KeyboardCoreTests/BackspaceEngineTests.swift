import Foundation
import CoreGraphics
import XCTest
@testable import KeyboardCore

final class BackspaceEngineTests: XCTestCase {
    func testFirstDeletionIsImmediateAndHoldRepeatsAfterBriefDelay() {
        let engine = BackspaceEngine()
        XCTAssertEqual(BackspaceEngine.initialDelay, 0.3, accuracy: 0.000_001)
        XCTAssertEqual(engine.nextInterval(heldFor: 0.3), BackspaceEngine.repeatInterval, accuracy: 0.000_001)
        XCTAssertEqual(engine.nextInterval(heldFor: 0.44), 0.05, accuracy: 0.000_001)
        XCTAssertEqual(engine.nextInterval(heldFor: 0.45), 0.03, accuracy: 0.000_001)
        XCTAssertEqual(engine.nextInterval(heldFor: 0.6), 0.2, accuracy: 0.000_001)
        XCTAssertEqual(engine.nextDeletion(heldFor: 0.59), .character)
        XCTAssertEqual(engine.nextDeletion(heldFor: 0.6), .word)
        XCTAssertEqual(engine.nextDeletion(heldFor: 0.6, contextBeforeInput: nil), .character)
        XCTAssertEqual(engine.nextDeletion(heldFor: 0.6, contextBeforeInput: ""), .character)
        XCTAssertEqual(engine.nextDeletion(heldFor: 0.6, contextBeforeInput: "hello\n"), .character)
        XCTAssertEqual(engine.nextDeletion(heldFor: 0.6, contextBeforeInput: "hello world "), .word)
        XCTAssertEqual(engine.nextDeletion(heldFor: .infinity), .character)
    }

    func testSwipeToDeleteRequiresLeftwardMostlyHorizontalMovement() {
        let engine = BackspaceEngine()
        XCTAssertTrue(engine.shouldSwipeDelete(start: .zero, current: CGPoint(x: -40, y: 8),
                                               repeated: false, enabled: true))
        XCTAssertFalse(engine.shouldSwipeDelete(start: .zero, current: CGPoint(x: -40, y: 30),
                                                repeated: false, enabled: true))
        XCTAssertFalse(engine.shouldSwipeDelete(start: .zero, current: CGPoint(x: -40, y: 0),
                                                repeated: true, enabled: true))
    }

    func testSynchronizedBufferTracksHostAfterEveryDeletion() throws {
        var engine = BackspaceEngine()
        engine.synchronizeBuffer(contextBeforeInput: "hello")
        XCTAssertTrue(engine.bufferMatches("hello"))
        XCTAssertFalse(engine.bufferMatches("hell"))

        engine.synchronizeBuffer(contextBeforeInput: "hell")
        XCTAssertTrue(engine.bufferMatches("hell"))
        let plan = try XCTUnwrap(engine.wordDeletionPlan(contextBeforeInput: "hello world "))
        XCTAssertEqual(plan.deletedText, "world ")

        engine.synchronizeBuffer(contextBeforeInput: nil)
        XCTAssertTrue(engine.bufferMatches(nil))
    }
}
