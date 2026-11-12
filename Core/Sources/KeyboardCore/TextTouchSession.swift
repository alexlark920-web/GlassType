import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// One finger, one committed character. Motion changes the selected text key;
/// UIKit's original hit-tested UIButton remains the event receiver throughout.
/// No predicted samples, text histories, arrays or per-move allocations.
public struct TextTouchSession {
    public enum Phase { case idle, tracking, ended, cancelled }
    public private(set) var phase: Phase = .idle
    public private(set) var selectedKey: Int?
    public private(set) var maximumTravel: CGFloat = 0
    private var start = CGPoint.zero
    private var initialKey = -1
    public init() {}

    public mutating func begin(at point: CGPoint, keyIndex: Int, model: TouchRecognizer) {
        cancel()
        guard point.x.isFinite, point.y.isFinite, model.geometry.keys.indices.contains(keyIndex),
              model.geometry.keys[keyIndex].role.character != nil else { return }
        start = point; initialKey = keyIndex; selectedKey = keyIndex
        maximumTravel = 0; phase = .tracking
    }
    @discardableResult public mutating func move(to point: CGPoint, model: TouchRecognizer) -> Int? {
        guard phase == .tracking, point.x.isFinite, point.y.isFinite else { selectedKey = nil; return nil }
        maximumTravel = max(maximumTravel, hypot(point.x - start.x, point.y - start.y))
        let bounds = model.geometry.bounds
        // A lift a few points beyond the outer edge must not lose an otherwise
        // valid character. Larger excursions cancel; function cells stay protected.
        let edgeTolerance = min(6, model.geometry.pitch.width * 0.18)
        guard bounds.insetBy(dx: -edgeTolerance, dy: -edgeTolerance).contains(point) else { selectedKey = nil; return nil }
        let clamped = CGPoint(x: min(bounds.maxX, max(bounds.minX, point.x)), y: min(bounds.maxY, max(bounds.minY, point.y)))
        guard let result = model.resolve(clamped), model.geometry.keys[result.first.keyIndex].role.character != nil else {
            selectedKey = nil; return nil
        }
        let winner = result.first.keyIndex
        guard let current = selectedKey, current != winner else { selectedKey = winner; return winner }
        let slop = min(5, max(2.5, model.geometry.pitch.width * 0.12))
        if current == initialKey && maximumTravel < slop { return current }
        let previousProbability: Double
        if let second = result.second, second.keyIndex == current { previousProbability = second.probability }
        else if let third = result.third, third.keyIndex == current { previousProbability = third.probability }
        else { previousProbability = 0 }
        // Hysteresis suppresses boundary flicker, while a deliberate slide can
        // retarget freely. This is a tunable engineering threshold, not a learned LM.
        if result.first.probability > previousProbability * 1.35 { selectedKey = winner }
        return selectedKey
    }
    public mutating func end(at point: CGPoint, model: TouchRecognizer) -> Int? {
        guard phase == .tracking else { return nil }
        let result = move(to: point, model: model)
        phase = .ended; selectedKey = nil
        return result
    }
    public mutating func cancel() { phase = .cancelled; selectedKey = nil; maximumTravel = 0 }
}
