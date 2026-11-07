import UIKit
import KeyboardCore
import UIKit.UIGestureRecognizerSubclass

final class GlideTouchRecognizer: UIGestureRecognizer {
    weak var coordinateView: UIView?
    var mayBegin: ((CGPoint, CGPoint) -> Bool)?
    private(set) var points: [CGPoint] = []
    private(set) var startPoint: CGPoint = .zero
    private weak var trackedTouch: UITouch?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = true
        delaysTouchesBegan = false; delaysTouchesEnded = false
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard trackedTouch == nil, touches.count == 1, let touch = touches.first else {
            state = state == .possible ? .failed : .cancelled; return
        }
        trackedTouch = touch
        startPoint = touch.location(in: coordinateView ?? view)
        points = [startPoint]
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch), state != .failed, state != .cancelled else { return }
        var activates = false
        for sample in event.coalescedTouches(for: touch) ?? [touch] {
            let point = sample.location(in: coordinateView ?? view)
            append(point)
            if state == .possible, mayBegin?(startPoint, point) == true { activates = true }
        }
        if state == .possible {
            if activates { state = .began }
        } else if state == .began || state == .changed { state = .changed }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch), state != .failed, state != .cancelled else { return }
        append(touch.location(in: coordinateView ?? view))
        state = state == .possible ? .failed : .ended
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = state == .possible ? .failed : .cancelled
    }
    override func reset() {
        super.reset(); trackedTouch = nil; points.removeAll(keepingCapacity: true); startPoint = .zero
    }
    func cancelCurrentTouch() {
        if state == .possible { state = .failed }
        else if state == .began || state == .changed { state = .cancelled }
    }
    private func append(_ point: CGPoint) {
        guard point.x.isFinite, point.y.isFinite else { return }
        if let last = points.last, hypot(point.x - last.x, point.y - last.y) < 1 { return }
        if points.count >= 384 { points = points.enumerated().filter { $0.offset % 2 == 0 }.map(\.element) }
        points.append(point)
    }
}
