import Foundation
import CoreGraphics

/// Timing and gesture policy for a held backspace key. UIKit owns the timer;
/// this value type keeps its repeat decisions deterministic and testable.
public struct BackspaceEngine: Sendable {
    public enum Deletion: Equatable, Sendable { case character, word }

    /// Delete one character on touch-down. Start repeats after a brief hold,
    /// then use the elapsed hold duration to accelerate them.
    public static let initialDelay: TimeInterval = 0.3
    public static let repeatInterval: TimeInterval = 0.05
    public static let acceleratedInterval: TimeInterval = 0.03
    public static let wordInterval: TimeInterval = 0.2
    /// Characters repeat through the first 0.6s of the hold, then whole words.
    public static let wordDeletionAfter: TimeInterval = 0.6
    /// Character repeats speed up before the hold escalates to words.
    public static let accelerationAfter: TimeInterval = 0.45

    public private(set) var synchronizedBuffer: String? = nil

    public init() {}

    /// The first character is removed on touch-down; held presses start
    /// repeating after 300 ms. Word deletion begins once the hold reaches 0.6s.
    public func nextDeletion(heldFor elapsed: TimeInterval) -> Deletion {
        elapsed.isFinite && elapsed >= Self.wordDeletionAfter ? .word : .character
    }

    /// Whole-word repeats require a live `documentContextBeforeInput`. An empty
    /// or unavailable context stays on character deletion.
    public func nextDeletion(heldFor elapsed: TimeInterval, contextBeforeInput: String?) -> Deletion {
        guard nextDeletion(heldFor: elapsed) == .word else { return .character }
        guard let contextBeforeInput, !contextBeforeInput.isEmpty, contextBeforeInput.last?.isNewline != true else { return .character }
        return .word
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
