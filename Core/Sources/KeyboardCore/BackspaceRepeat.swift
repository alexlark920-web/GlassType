import Foundation

public enum BackspaceRepeat {
    /// The initial character is deleted on touch-down; repeat begins shortly after.
    public static let initialDelay: TimeInterval = 0.09
    public static func interval(heldFor elapsed: TimeInterval) -> TimeInterval {
        guard elapsed.isFinite, elapsed >= 0 else { return 0.055 }
        if elapsed >= 2 { return 0.03 }
        if elapsed >= 0.9 { return 0.04 }
        return 0.055
    }
}
