import UIKit
import KeyboardCore

/// A single hit-test owner routes each touch to exactly one existing UIButton.
/// No overlapping enlarged subviews, gesture-consuming overlay, or text edits.
final class KeyboardTouchSurface: UIView {
    var language: KeyboardLanguage = .english
    var symbolPage: SymbolPage?
    var customRows: [[String]]?
    var thirdRowUsesModeSwitch = false
    var compact = true
    var needsSystemKey = false
    var keyViews: [UIButton] = []
    var didLayoutKey: ((UIButton, KeyboardKeyGeometry) -> Void)?
    var canLearn: (() -> Bool)?
    var didLearn: ((Double, Double) -> Void)?
    var didSelectTextKey: ((UIButton) -> Void)?
    var didFinishTextKey: ((UIButton, Bool) -> Void)?
    var didChangePress: ((UIButton, Bool) -> Void)?
    var canCommitText: (() -> Bool)?
    private(set) var revision: UInt = 0
    private var presses: [UInt8] = []
    private(set) var recognizer: TouchRecognizer?
    private var configuration = TouchRecognitionConfiguration()
    private var previousBounds: CGRect = .null
    private let debug = TouchZoneOverlay()
    private var glassContainer: UIVisualEffectView?
    var showsDebugZones = false { didSet { updateDebug() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear; isOpaque = false; isMultipleTouchEnabled = true
        if #available(iOS 26.0, *) {
            let effect = UIGlassContainerEffect()
            // Neighbouring caps must stay distinct, even when highlighted.
            effect.spacing = 0
            let container = UIVisualEffectView(effect: effect)
            container.isMultipleTouchEnabled = true
            addSubview(container); glassContainer = container
        }
        debug.isUserInteractionEnabled = false; debug.isAccessibilityElement = false
        addSubview(debug)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func addKey(_ button: UIButton) { (glassContainer?.contentView ?? self).addSubview(button) }
    func invalidateGeometry() { revision &+= 1; resetPresses(); previousBounds = .null; setNeedsLayout() }
    func setConfiguration(_ value: TouchRecognitionConfiguration) {
        if value.offsetX != configuration.offsetX || value.offsetY != configuration.offsetY ||
           value.sigmaX != configuration.sigmaX || value.sigmaY != configuration.sigmaY || value.languageWeight != configuration.languageWeight {
            revision &+= 1; resetPresses()
        }
        configuration = value
        if let geometry = recognizer?.geometry { recognizer = TouchRecognizer(geometry: geometry, configuration: value) }
        updateDebug()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        glassContainer?.frame = bounds
        guard bounds != previousBounds else { return }
        revision &+= 1; resetPresses()
        previousBounds = bounds
        let geometry = KeyboardGeometry.make(bounds: bounds, language: language, symbolPage: symbolPage,
                                              compact: compact, needsSystemKey: needsSystemKey,
                                              customRows: customRows, thirdRowUsesModeSwitch: thirdRowUsesModeSwitch)
        guard geometry.keys.count == keyViews.count else { recognizer = nil; return }
        recognizer = TouchRecognizer(geometry: geometry, configuration: configuration)
        presses = Array(repeating: 0, count: keyViews.count)
        for key in geometry.keys {
            let button = keyViews[key.index]
            button.frame = key.slotFrame
            didLayoutKey?(button, key)
        }
        debug.frame = bounds; bringSubviewToFront(debug); updateDebug()
    }
    func keyIndex(at point: CGPoint) -> Int? { recognizer?.resolve(point)?.first.keyIndex }
    func changeSelection(from previous: Int?, to selected: Int?, revision token: UInt) {
        guard token == revision, previous != selected else { return }
        if let previous, presses.indices.contains(previous), presses[previous] > 0 {
            presses[previous] -= 1; didChangePress?(keyViews[previous], presses[previous] > 0)
        }
        if let selected, presses.indices.contains(selected) {
            presses[selected] = min(8, presses[selected] + 1)
            didChangePress?(keyViews[selected], true)
            didSelectTextKey?(keyViews[selected])
        }
    }
    func finishSelection(_ index: Int?, cancelled: Bool, revision token: UInt) {
        guard token == revision, let index, keyViews.indices.contains(index) else { return }
        didFinishTextKey?(keyViews[index], cancelled)
        changeSelection(from: index, to: nil, revision: token)
    }
    private func resetPresses() {
        for index in presses.indices where presses[index] > 0 && keyViews.indices.contains(index) {
            didChangePress?(keyViews[index], false)
        }
        presses.removeAll(keepingCapacity: true)
    }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }
        if previousBounds != bounds { layoutIfNeeded() }
        guard let index = keyIndex(at: point), keyViews.indices.contains(index) else { return nil }
        let button = keyViews[index]
        return button.isEnabled && button.isUserInteractionEnabled && !button.isHidden ? button : nil
    }
    struct LearningSample {
        let point: CGPoint
        let time: TimeInterval
        let x: Double
        let y: Double
    }
    func learningSample(at point: CGPoint, keyIndex: Int, time: TimeInterval) -> LearningSample? {
        guard canLearn?() == true, let model = recognizer, model.geometry.keys.indices.contains(keyIndex),
              let result = model.resolve(point), result.first.keyIndex == keyIndex, result.first.geometricProbability >= 0.76,
              model.geometry.keys[keyIndex].role.character?.allSatisfy(\.isLetter) == true else { return nil }
        let center = model.geometry.keys[keyIndex].center
        let x = Double((point.x - center.x) / model.geometry.pitch.width)
        let y = Double((point.y - center.y) / model.geometry.pitch.height)
        guard abs(x) <= 0.42, abs(y) <= 0.42 else { return nil }
        return LearningSample(point: point, time: time, x: x, y: y)
    }
    func finishSample(_ sample: LearningSample, at point: CGPoint, time: TimeInterval, maximumDuration: TimeInterval) {
        guard canLearn?() == true, time >= sample.time, time - sample.time < maximumDuration,
              hypot(point.x - sample.point.x, point.y - sample.point.y) < 7 else { return }
        didLearn?(sample.x, sample.y)
    }
    private func updateDebug() {
        debug.isHidden = !showsDebugZones
        debug.zones = showsDebugZones ? recognizer?.debugZones() ?? [] : []
        debug.centers = showsDebugZones ? recognizer?.geometry.keys.map(\.center) ?? [] : []
        debug.setNeedsDisplay()
    }
}

private final class TouchZoneOverlay: UIView {
    var zones: [TouchDebugZone] = []
    var centers: [CGPoint] = []
    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear; isOpaque = false }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ rect: CGRect) {
        for zone in zones {
            guard let first = zone.polygon.first else { continue }
            let path = UIBezierPath(); path.move(to: first)
            for point in zone.polygon.dropFirst() { path.addLine(to: point) }
            path.close(); path.lineWidth = 0.6
            let color = UIColor(hue: CGFloat((zone.keyIndex * 137) % 360) / 360, saturation: 0.8, brightness: 1, alpha: 1)
            color.withAlphaComponent(0.13).setFill(); path.fill()
            color.withAlphaComponent(0.8).setStroke(); path.stroke()
        }
        UIColor.label.setFill()
        for point in centers { UIBezierPath(ovalIn: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3)).fill() }
    }
}
