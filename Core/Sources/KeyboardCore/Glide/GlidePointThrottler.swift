import CoreGraphics
import Foundation

/// Limits recorded glide samples while preserving fast, meaningful turns.
public struct GlidePointThrottler: Sendable {
    public let minimumInterval: TimeInterval
    public let significantShift: CGFloat
    private var lastPoint: CGPoint?
    private var lastTimestamp: TimeInterval?

    public init(minimumInterval: TimeInterval = 0.03, significantShift: CGFloat = 4) {
        self.minimumInterval = max(0, minimumInterval)
        self.significantShift = max(0, significantShift)
    }

    public mutating func reset() {
        lastPoint = nil
        lastTimestamp = nil
    }

    /// Returns true for the first point, after the time interval, or after a
    /// significant movement. Timestamps are monotonic touch timestamps.
    public mutating func shouldAccept(_ point: CGPoint, at timestamp: TimeInterval) -> Bool {
        guard point.x.isFinite, point.y.isFinite, timestamp.isFinite else { return false }
        guard let previous = lastPoint, let previousTime = lastTimestamp else {
            lastPoint = point
            lastTimestamp = timestamp
            return true
        }
        let dx = point.x - previous.x, dy = point.y - previous.y
        guard timestamp - previousTime >= minimumInterval || dx * dx + dy * dy >= significantShift * significantShift else { return false }
        lastPoint = point
        lastTimestamp = max(previousTime, timestamp)
        return true
    }
}
