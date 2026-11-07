import Foundation

public enum LanguageDirection: Equatable { case previous, next }

/// One touch has exactly one role: space, quick language swipe, or trackpad.
/// Coordinates are points, time is monotonic seconds; no timers or UIKit here.
public struct SpacebarInteraction {
    public enum Phase: Equatable { case idle, pressing, swiping, cursor, cancelled }
    public enum Action: Equatable {
        case none, insertSpace, cursorBegan
        case changeLanguage(LanguageDirection)
        case moveCursor(Int)
    }
    public private(set) var phase: Phase = .idle
    public static let holdDuration = 0.42
    public static let maximumSwipeDuration = 0.32
    public static let swipeDistance = 36.0
    public static let cursorStep = 8.0
    private var startX = 0.0, startY = 0.0, startTime = 0.0
    private var lastX = 0.0, lastY = 0.0, cursorAnchor = 0.0
    private var holdEligible = true
    public init() {}

    public mutating func begin(x: Double, y: Double, at time: Double) {
        reset()
        guard x.isFinite, y.isFinite, time.isFinite else { phase = .cancelled; return }
        phase = .pressing
        startX = x; lastX = x; startY = y; lastY = y; startTime = time
    }
    public mutating func update(x: Double, y: Double, at time: Double) -> Action {
        guard phase != .idle, phase != .cancelled else { return .none }
        guard x.isFinite, y.isFinite, time.isFinite else { cancel(); return .none }
        lastX = x; lastY = y
        if phase == .cursor {
            let offset = (x - cursorAnchor) / Self.cursorStep
            let steps = Int(min(32, max(-32, offset)))
            guard steps != 0 else { return .none }
            cursorAnchor += Double(steps) * Self.cursorStep
            return .moveCursor(steps)
        }
        guard phase == .pressing else { return .none }
        let dx = x - startX, dy = y - startY
        let elapsed = time - startTime
        if abs(dx) > 12 || abs(dy) > 12 { holdEligible = false }
        if abs(dy) > 24 && abs(dy) > abs(dx) * 0.75 { phase = .cancelled; return .none }
        if elapsed <= Self.maximumSwipeDuration && elapsed >= 0 && abs(dx) >= Self.swipeDistance && abs(dy) <= abs(dx) * 0.55 {
            phase = .swiping; return .none
        }
        if elapsed > Self.maximumSwipeDuration && (abs(dx) > 18 || abs(dy) > 18) {
            phase = .cancelled; return .none
        }
        return hold(at: time)
    }
    /// Called by the UI's hold timer as well as touch updates.
    public mutating func hold(at time: Double) -> Action {
        guard phase == .pressing, holdEligible, time.isFinite,
              time - startTime >= Self.holdDuration else { return .none }
        phase = .cursor; cursorAnchor = lastX
        return .cursorBegan
    }
    public mutating func end(x: Double, y: Double, at time: Double) -> Action {
        let movement = update(x: x, y: y, at: time)
        let result: Action
        switch phase {
        case .pressing:
            result = time - startTime >= 0 && time - startTime < Self.holdDuration && abs(x - startX) <= 18 && abs(y - startY) <= 18 ? .insertSpace : .none
        case .swiping:
            let dx = x - startX, dy = y - startY
            if time - startTime <= Self.maximumSwipeDuration && time - startTime >= 0 && abs(dx) >= Self.swipeDistance && abs(dy) <= abs(dx) * 0.55 {
                result = .changeLanguage(dx < 0 ? .next : .previous)
            } else { result = .none }
        case .cursor:
            if case .moveCursor = movement { result = movement } else { result = .none }
        case .idle, .cancelled: result = .none
        }
        reset()
        return result
    }
    public mutating func cancel() { reset() }
    private mutating func reset() {
        phase = .idle; holdEligible = true
        startX = 0; startY = 0; startTime = 0; lastX = 0; lastY = 0; cursorAnchor = 0
    }
}
