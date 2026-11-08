import Foundation
import CoreGraphics

/// Timing and gesture policy for a held backspace key. UIKit owns the timer;
/// this value type keeps its repeat decisions deterministic and testable.
public struct BackspaceEngine: Sendable {
    public enum Deletion: Equatable, Sendable { case character, word }

    /// The first character is deleted on touch-down; start repeating almost
    /// immediately so a held key does not appear to pause after that deletion.
    public static let initialDelay: TimeInterval = 0.05
    public static let repeatInterval: TimeInterval = 0.05
    public static let acceleratedInterval: TimeInterval = 0.03
    public static let wordInterval: TimeInterval = 0.2
    public static let wordDeletionAfter: TimeInterval = 1.6
    public static let accelerationAfter: TimeInterval = 0.8

    public private(set) var synchronizedBuffer: String? = nil

    public init() {}

    /// The first character is removed on touch-down; held presses repeat after
    /// a short 50 ms interval.
    public func nextDeletion(heldFor elapsed: TimeInterval) -> Deletion {
        elapsed.isFinite && elapsed >= Self.wordDeletionAfter ? .word : .character
    }

    public func nextInterval(heldFor elapsed: TimeInterval) -> TimeInterval {
        guard elapsed.isFinite, elapsed >= 0 else { return Self.repeatInterval }
        if elapsed >= Self.wordDeletionAfter { return Self.wordInterval }
        return elapsed >= Self.accelerationAfter ? Self.acceleratedInterval : Self.repeatInterval
    }

    public func shouldSwipeDelete(start: CGPoint, current: CGPoint, repeated: Bool,
                                  enabled: Bool) -> Bool {
        guard enabled, !repeated else { return false }
        let dx = current.x - start.x, dy = current.y - start.y
        return dx < -32 && abs(dy) < abs(dx) * 0.6
    }

    /// Records the host document's authoritative input context after each
    /// mutation so predictions never use a stale keyboard-side buffer.
    public mutating func synchronizeBuffer(contextBeforeInput: String?) {
        synchronizedBuffer = contextBeforeInput
    }

    public func bufferMatches(_ contextBeforeInput: String?) -> Bool {
        synchronizedBuffer == contextBeforeInput
    }

    public func wordDeletionPlan(contextBeforeInput: String,
                                 contextIsComplete: Bool = false) -> WordDeletionPlan? {
        WordDeletionPlan.make(contextBeforeInput: contextBeforeInput,
                              contextIsComplete: contextIsComplete)
    }
}
