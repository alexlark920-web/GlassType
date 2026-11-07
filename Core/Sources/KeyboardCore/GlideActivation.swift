import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum GlideActivation {
    /// A little finger jitter must still produce a tap. This predicate is
    /// evaluated for raw/coalesced samples, never as a premature pan veto.
    public static func shouldBegin(start: CGPoint, current: CGPoint, startKey: Int?, currentKey: Int?) -> Bool {
        guard let startKey, let currentKey, startKey != currentKey,
              start.x.isFinite, start.y.isFinite, current.x.isFinite, current.y.isFinite else { return false }
        return hypot(current.x - start.x, current.y - start.y) >= 7
    }
}
