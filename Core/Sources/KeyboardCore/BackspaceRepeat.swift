import Foundation

public enum BackspaceRepeat {
    /// The initial character is deleted on touch-down; repeats begin after a
    /// deliberate hold to avoid accidental multi-character deletion.
    public static let initialDelay: TimeInterval = BackspaceEngine.initialDelay
    public static func interval(heldFor elapsed: TimeInterval) -> TimeInterval {
        BackspaceEngine().nextInterval(heldFor: elapsed)
    }
}
