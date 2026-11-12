import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum GlideActivation {
    /// A little finger jitter must still produce a tap. This predicate is
    /// evaluated for raw/coalesced samples, never as a premature pan veto.
    public static func shouldBegin(start: CGPoint, current: CGPoint, startKey: Int?, currentKey: Int?, minimumDistance: CGFloat = 7) -> Bool {
        guard let startKey, let currentKey, startKey != currentKey,
              start.x.isFinite, start.y.isFinite, current.x.isFinite, current.y.isFinite else { return false }
        let threshold = minimumDistance.isFinite ? max(7, minimumDistance) : 7
        return hypot(current.x - start.x, current.y - start.y) >= threshold
    }
    public static func minimumTravel(
        keyPitch: CGSize,
        minimumPoints: CGFloat = KeyboardTuningConfig.current.glideActivationThresholdPoints
    ) -> CGFloat {
        let floor = minimumPoints.isFinite ? minimumPoints : KeyboardTuningConfig.current.glideActivationThresholdPoints
        return max(floor, min(24, keyPitch.width * 0.6))
    }
    public static func isShortStroke(_ points: [CGPoint], keyPitch: CGSize) -> Bool {
        guard points.count >= 2, keyPitch.width > 0, keyPitch.height > 0 else { return false }
        var length: CGFloat = 0
        for index in 1..<points.count {
            let dx = (points[index].x - points[index - 1].x) / keyPitch.width
            let dy = (points[index].y - points[index - 1].y) / keyPitch.height
            guard dx.isFinite, dy.isFinite else { return false }
            length += hypot(dx, dy)
            if length >= 0.85 { return false }
        }
        return true
    }
}
