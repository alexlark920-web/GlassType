import UIKit
import KeyboardCore
import UIKit.UIGestureRecognizerSubclass

final class GlideTouchRecognizer: UIGestureRecognizer {
    weak var coordinateView: UIView?
    var mayBegin: ((CGPoint, CGPoint) -> Bool)?
    private(set) var points: [CGPoint] = []
    private(set) var startPoint: CGPoint = .zero
    private weak var trackedTouch: UITouch?
    private var pointThrottler = GlidePointThrottler()

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = true
        delaysTouchesBegan = false; delaysTouchesEnded = false
        points.reserveCapacity(384)
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard trackedTouch == nil, touches.count == 1, let touch = touches.first else {
            state = state == .possible ? .failed : .cancelled; return
        }
        trackedTouch = touch
        startPoint = touch.location(in: coordinateView ?? view)
        pointThrottler.reset()
        points.removeAll(keepingCapacity: true)
        points.append(startPoint)
        _ = pointThrottler.shouldAccept(startPoint, at: touch.timestamp)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch), state != .failed, state != .cancelled else { return }
        var activates = false
        if let samples = event.coalescedTouches(for: touch) {
            for sample in samples {
                let point = sample.location(in: coordinateView ?? view)
                append(point, at: sample.timestamp)
                if state == .possible, mayBegin?(startPoint, point) == true { activates = true }
            }
        } else {
            let point = touch.location(in: coordinateView ?? view)
            append(point, at: touch.timestamp)
            if state == .possible, mayBegin?(startPoint, point) == true { activates = true }
        }
        if state == .possible {
            if activates { state = .began }
        } else if state == .began || state == .changed { state = .changed }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch), state != .failed, state != .cancelled else { return }
        append(touch.location(in: coordinateView ?? view), at: touch.timestamp, force: true)
        state = state == .possible ? .failed : .ended
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = state == .possible ? .failed : .cancelled
    }
    override func reset() {
        super.reset(); trackedTouch = nil; points.removeAll(keepingCapacity: true); startPoint = .zero; pointThrottler.reset()
    }
    func cancelCurrentTouch() {
        if state == .possible { state = .failed }
        else if state == .began || state == .changed { state = .cancelled }
    }
    private func append(_ point: CGPoint, at timestamp: TimeInterval, force: Bool = false) {
        guard point.x.isFinite, point.y.isFinite else { return }
        if let last = points.last {
            let dx = point.x - last.x, dy = point.y - last.y
            if dx * dx + dy * dy < 1 { return }
        }
        guard force || pointThrottler.shouldAccept(point, at: timestamp) else { return }
        if force { _ = pointThrottler.shouldAccept(point, at: timestamp) }
        if points.count >= 384 {
            var write = 0
            var read = 0
            while read < points.count {
                points[write] = points[read]
                write += 1
                read += 2
            }
            points.removeSubrange(write..<points.count)
        }
        points.append(point)
    }
}
