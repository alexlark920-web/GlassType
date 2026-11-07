import UIKit
import KeyboardCore

/// Character caps may lift. Function keys and the entire bottom row only change
/// brightness; their hit targets always stay in place.
private enum KeyPressBehavior: Equatable { case character, function, spacebar }

private class KeyButton: UIButton {
    private let face = UIView()
    private let pressShade = UIView()
    private let sheen = CAGradientLayer()
    private var trackpadAppearance = false
    var showsCharacterPreview = false
    weak var touchSurface: KeyboardTouchSurface?
    var geometryIndex = -1
    var visualCapFrame: CGRect? { didSet { setNeedsLayout() } }
    var learningMaximumDuration: TimeInterval = 0.4
    private var learningSample: KeyboardTouchSurface.LearningSample?

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if let surface = touchSurface, geometryIndex >= 0 {
            return surface.keyIndex(at: convert(point, to: surface)) == geometryIndex
        }
        return super.point(inside: point, with: event)
    }
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let result = super.beginTracking(touch, with: event)
        if result, let surface = touchSurface {
            learningSample = surface.learningSample(at: touch.location(in: surface), keyIndex: geometryIndex, time: touch.timestamp)
        }
        return result
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if let sample = learningSample, let touch, let surface = touchSurface,
           surface.keyIndex(at: touch.location(in: surface)) == geometryIndex {
            surface.finishSample(sample, at: touch.location(in: surface), time: touch.timestamp, maximumDuration: learningMaximumDuration)
        }
        learningSample = nil; super.endTracking(touch, with: event)
    }
    override func cancelTracking(with event: UIEvent?) {
        learningSample = nil; super.cancelTracking(with: event)
    }
    var pressBehavior: KeyPressBehavior = .function {
        didSet { updatePressAppearance(animated: false) }
    }
    var fillColor: UIColor = .clear { didSet { refreshSurface() } }
    var compact = true { didSet { setNeedsLayout() } }
    var keyRadius: CGFloat = 7.5 { didSet { setNeedsLayout() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear; isExclusiveTouch = false
        face.isUserInteractionEnabled = false; face.isAccessibilityElement = false
        face.layer.cornerCurve = .continuous
        face.layer.shadowColor = UIColor.black.cgColor
        face.layer.shadowRadius = 2.5; face.layer.shadowOffset = CGSize(width: 0, height: 1.5)
        sheen.startPoint = CGPoint(x: 0.5, y: 0); sheen.endPoint = CGPoint(x: 0.5, y: 1)
        sheen.locations = [0, 0.42, 1]; sheen.masksToBounds = true
        face.layer.addSublayer(sheen)
        pressShade.backgroundColor = .white; pressShade.alpha = 0
        pressShade.isUserInteractionEnabled = false; pressShade.isAccessibilityElement = false
        pressShade.layer.cornerCurve = .continuous
        face.addSubview(pressShade); insertSubview(face, at: 0)
        NotificationCenter.default.addObserver(self, selector: #selector(accessibilityAppearanceChanged), name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
        refreshSurface()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let fallback = bounds.insetBy(dx: compact ? min(3.4, max(2.2, bounds.width * 0.09)) : 3,
                                     dy: bounds.height >= 42 ? 5 : 3.5)
        let cap = visualCapFrame ?? fallback
        face.bounds = CGRect(origin: .zero, size: cap.size)
        face.center = CGPoint(x: cap.midX, y: cap.midY)
        face.layer.cornerRadius = keyRadius
        pressShade.frame = face.bounds; pressShade.layer.cornerRadius = keyRadius
        CATransaction.begin(); CATransaction.setDisableActions(true)
        sheen.frame = face.bounds; sheen.cornerRadius = keyRadius
        face.layer.shadowPath = face.bounds.isEmpty ? nil : UIBezierPath(roundedRect: face.bounds, cornerRadius: keyRadius).cgPath
        CATransaction.commit()
        sendSubviewToBack(face)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        refreshSurface()
    }
    @objc private func accessibilityAppearanceChanged() { refreshSurface() }
    private func refreshSurface() {
        let dark = traitCollection.userInterfaceStyle == .dark
        let contrast = traitCollection.accessibilityContrast == .high
        let reduced = UIAccessibility.isReduceTransparencyEnabled
        let resolved = fillColor.resolvedColor(with: traitCollection)
        face.backgroundColor = reduced ? resolved.withAlphaComponent(1) : resolved
        face.layer.borderWidth = contrast ? 1 : 0.5
        face.layer.borderColor = UIColor.white.withAlphaComponent(contrast ? (dark ? 0.42 : 0.95) : (dark ? 0.14 : 0.65)).cgColor
        CATransaction.begin(); CATransaction.setDisableActions(true)
        sheen.colors = [UIColor.white.withAlphaComponent(dark ? 0.12 : 0.35).cgColor,
                        UIColor.white.withAlphaComponent(dark ? 0.025 : 0.055).cgColor,
                        UIColor.clear.cgColor]
        sheen.opacity = reduced ? 0 : 1
        CATransaction.commit()
        updatePressAppearance(animated: false)
    }
    func setTrackpadAppearance(_ enabled: Bool) {
        trackpadAppearance = enabled
        for child in subviews { child.layer.removeAllAnimations() }
        pressShade.layer.removeAllAnimations()
        if enabled { isHighlighted = false }
        updatePressAppearance(animated: false)
    }
    override var isHighlighted: Bool {
        didSet {
            guard oldValue != isHighlighted else { return }
            updatePressAppearance(animated: true)
        }
    }
    private func updatePressAppearance(animated: Bool) {
        let down = isHighlighted && !trackpadAppearance
        let dark = traitCollection.userInterfaceStyle == .dark
        let reducedMotion = UIAccessibility.isReduceMotionEnabled
        let lifts = pressBehavior == .character
        let pressedAlpha: CGFloat
        switch pressBehavior {
        case .character: pressedAlpha = dark ? 0.14 : 0.20
        case .function: pressedAlpha = dark ? 0.085 : 0.14
        case .spacebar: pressedAlpha = dark ? 0.065 : 0.17
        }
        let changes = {
            self.face.alpha = self.trackpadAppearance ? 0.30 : 1
            self.pressShade.alpha = down ? pressedAlpha : 0
            let transform = down && lifts && !reducedMotion ? CGAffineTransform(translationX: 0, y: -2.2).scaledBy(x: 1.025, y: 1.035) : .identity
            self.face.transform = transform
            self.face.layer.shadowOpacity = self.trackpadAppearance ? 0 : (down && lifts ? (dark ? 0.22 : 0.14) : (dark ? 0.10 : 0.07))
            for child in self.subviews where child !== self.face {
                child.transform = transform
                child.alpha = self.trackpadAppearance ? 0 : 1
            }
        }
        if !animated || reducedMotion { changes() }
        else if !lifts {
            UIView.animate(withDuration: 0.09, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut], animations: changes)
        } else {
            UIView.animate(withDuration: down ? 0.12 : 0.24, delay: 0,
                           usingSpringWithDamping: down ? 0.74 : 0.64,
                           initialSpringVelocity: down ? 0.7 : 0.9,
                           options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
        }
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}

/// One reusable silhouette, always clamped to the extension's bounds.
private final class KeyPreviewView: UIView {
    private let silhouette = CAShapeLayer()
    private let glyph = UILabel()
    private let symbol = UIImageView()
    private var stemCenterX: CGFloat = 0
    private var stemWidth: CGFloat = 0
    private var fill: UIColor = .secondarySystemBackground
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear; isOpaque = false
        isUserInteractionEnabled = false; isAccessibilityElement = false
        layer.addSublayer(silhouette)
        layer.shadowColor = UIColor.black.cgColor; layer.shadowOpacity = 0.20
        layer.shadowRadius = 3; layer.shadowOffset = CGSize(width: 0, height: 2)
        glyph.textAlignment = .center; glyph.adjustsFontSizeToFitWidth = true
        glyph.minimumScaleFactor = 0.75; glyph.isAccessibilityElement = false
        addSubview(glyph)
        symbol.contentMode = .scaleAspectFit; symbol.isAccessibilityElement = false; symbol.isHidden = true; addSubview(symbol)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(layout: KeyPreviewLayout, text: String, fill: UIColor, ink: UIColor) {
        frame = layout.frame; stemCenterX = layout.stemCenterX; stemWidth = layout.stemWidth
        self.fill = fill; glyph.text = text; glyph.textColor = ink
        symbol.image = nil; symbol.isHidden = true
        silhouette.fillColor = fill.resolvedColor(with: traitCollection).cgColor
        setNeedsLayout(); layoutIfNeeded()
    }
    func configureSymbol(layout: KeyPreviewLayout, name: String, fill: UIColor, ink: UIColor) {
        configure(layout: layout, text: "", fill: fill, ink: ink)
        symbol.image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .medium))
        symbol.tintColor = ink; symbol.isHidden = false; setNeedsLayout(); layoutIfNeeded()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height >= 24 else {
            silhouette.path = nil; layer.shadowPath = nil; glyph.frame = .zero; return
        }
        let bubbleHeight = max(1, bounds.height - 12)
        let width = bounds.width
        let radius: CGFloat = min(10, bubbleHeight / 3)
        let left = stemCenterX - stemWidth / 2, right = stemCenterX + stemWidth / 2
        let path = UIBezierPath()
        path.move(to: CGPoint(x: radius, y: 0))
        path.addLine(to: CGPoint(x: width - radius, y: 0))
        path.addQuadCurve(to: CGPoint(x: width, y: radius), controlPoint: CGPoint(x: width, y: 0))
        path.addLine(to: CGPoint(x: width, y: bubbleHeight - radius))
        path.addQuadCurve(to: CGPoint(x: width - radius, y: bubbleHeight), controlPoint: CGPoint(x: width, y: bubbleHeight))
        path.addLine(to: CGPoint(x: min(width - radius, right + 4), y: bubbleHeight))
        path.addQuadCurve(to: CGPoint(x: right, y: bubbleHeight + 4), controlPoint: CGPoint(x: right, y: bubbleHeight))
        path.addLine(to: CGPoint(x: right, y: bounds.height - 3))
        path.addQuadCurve(to: CGPoint(x: right - 3, y: bounds.height), controlPoint: CGPoint(x: right, y: bounds.height))
        path.addLine(to: CGPoint(x: left + 3, y: bounds.height))
        path.addQuadCurve(to: CGPoint(x: left, y: bounds.height - 3), controlPoint: CGPoint(x: left, y: bounds.height))
        path.addLine(to: CGPoint(x: left, y: bubbleHeight + 4))
        path.addQuadCurve(to: CGPoint(x: max(radius, left - 4), y: bubbleHeight), controlPoint: CGPoint(x: left, y: bubbleHeight))
        path.addLine(to: CGPoint(x: radius, y: bubbleHeight))
        path.addQuadCurve(to: CGPoint(x: 0, y: bubbleHeight - radius), controlPoint: CGPoint(x: 0, y: bubbleHeight))
        path.addLine(to: CGPoint(x: 0, y: radius))
        path.addQuadCurve(to: CGPoint(x: radius, y: 0), controlPoint: CGPoint(x: 0, y: 0))
        path.close()
        silhouette.frame = bounds; silhouette.path = path.cgPath; layer.shadowPath = path.cgPath
        glyph.frame = CGRect(x: 4, y: 0, width: max(0, bounds.width - 8), height: bubbleHeight)
        glyph.font = .systemFont(ofSize: min(34, max(25, bubbleHeight - 10)))
        symbol.frame = CGRect(x: (bounds.width - 28) / 2, y: max(0, (bubbleHeight - 28) / 2), width: 28, height: 28)
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        silhouette.fillColor = fill.resolvedColor(with: traitCollection).cgColor
    }
}

/// UIButton tracking owns the whole touch, so swipe/hold never also insert a
/// space. Accessibility activation remains a normal space action.
private final class SpacebarButton: KeyButton {
    var onAction: ((SpacebarInteraction.Action) -> Void)?
    var onCursorEnd: (() -> Void)?
    private var interaction = SpacebarInteraction()
    private var holdTimer: Timer?
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        cancelInteraction()
        _ = super.beginTracking(touch, with: event)
        let point = touch.location(in: self)
        interaction.begin(x: Double(point.x), y: Double(point.y), at: ProcessInfo.processInfo.systemUptime)
        isHighlighted = true
        let timer = Timer(timeInterval: SpacebarInteraction.holdDuration, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.onAction?(self.interaction.hold(at: ProcessInfo.processInfo.systemUptime))
            self.holdTimer = nil
        }
        holdTimer = timer; RunLoop.main.add(timer, forMode: .common)
        return true
    }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let point = touch.location(in: self)
        onAction?(interaction.update(x: Double(point.x), y: Double(point.y), at: ProcessInfo.processInfo.systemUptime))
        return true
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        holdTimer?.invalidate(); holdTimer = nil
        let action: SpacebarInteraction.Action
        if let touch {
            let point = touch.location(in: self)
            action = interaction.end(x: Double(point.x), y: Double(point.y), at: ProcessInfo.processInfo.systemUptime)
        } else { interaction.cancel(); action = .none }
        super.endTracking(touch, with: event)
        isHighlighted = false
        onAction?(action)
        onCursorEnd?()
    }
    override func cancelTracking(with event: UIEvent?) {
        cancelInteraction()
        super.cancelTracking(with: event)
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cancelInteraction() }
    }
    func cancelInteraction() {
        let wasCursor = interaction.phase == .cursor
        holdTimer?.invalidate(); holdTimer = nil; interaction.cancel(); isHighlighted = false
        if wasCursor { onCursorEnd?() }
    }
    override func accessibilityActivate() -> Bool { onAction?(.insertSpace); return true }
    deinit { holdTimer?.invalidate() }
}

private final class DeleteKeyButton: KeyButton {
    var deleteAction: (() -> Void)?
    var deleteWordAction: (() -> Void)?
    var canSwipeWord: (() -> Bool)?
    private var delay: Timer?, repeatTimer: Timer?
    private var start: CGPoint = .zero
    private var swiped = false, repeated = false, deleteGestureActive = false
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        cancelInteraction(); _ = super.beginTracking(touch, with: event)
        deleteGestureActive = true; start = touch.location(in: self); isHighlighted = true
        let timer = Timer(timeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self, self.deleteGestureActive, !self.swiped else { return }
            self.repeated = true; self.deleteAction?()
            guard self.deleteGestureActive else { return }
            let repeating = Timer(timeInterval: 0.075, repeats: true) { [weak self] _ in
                guard let self, self.deleteGestureActive else { return }; self.deleteAction?()
            }
            self.repeatTimer = repeating; RunLoop.main.add(repeating, forMode: .common)
        }
        delay = timer; RunLoop.main.add(timer, forMode: .common)
        return true
    }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard deleteGestureActive else { return false }
        let p = touch.location(in: self)
        if !repeated, canSwipeWord?() == true, p.x - start.x < -32, abs(p.y - start.y) < abs(p.x - start.x) * 0.6 {
            swiped = true; delay?.invalidate(); delay = nil
        }
        if !bounds.contains(p), !swiped {
            delay?.invalidate(); delay = nil; repeatTimer?.invalidate(); repeatTimer = nil
            if repeated { isHighlighted = false }
        }
        return true
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        guard deleteGestureActive else { super.endTracking(touch, with: event); return }
        let p = touch?.location(in: self) ?? start
        let eligible = !repeated && canSwipeWord?() == true
        let word = (swiped || eligible) && p.x - start.x < -32 && abs(p.y - start.y) < abs(p.x - start.x) * 0.6
        let tap = !swiped && !repeated && touch != nil && bounds.contains(p)
        cancelInteraction(); super.endTracking(touch, with: event)
        if word { deleteWordAction?() } else if tap { deleteAction?() }
    }
    override func cancelTracking(with event: UIEvent?) { cancelInteraction(); super.cancelTracking(with: event) }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { cancelInteraction() } }
    func cancelInteraction() { deleteGestureActive = false; delay?.invalidate(); delay = nil; repeatTimer?.invalidate(); repeatTimer = nil; swiped = false; repeated = false; isHighlighted = false }
    override func accessibilityActivate() -> Bool { deleteAction?(); return true }
    deinit { delay?.invalidate(); repeatTimer?.invalidate() }
}

/// UIKit adapter uses the device's local dictionary, without learning words.
private final class SystemSpelling {
    private let checker = UITextChecker()
    func check(_ word: String, language: KeyboardLanguage) -> (known: Bool, candidates: [String]) {
        let available = UITextChecker.availableLanguages
        let preferred: String
        switch language {
        case .english: preferred = "en_US"
        case .russian: preferred = "ru_RU"
        case .ukrainian: preferred = "uk_UA"
        }
        guard let code = available.first(where: { $0 == preferred }) ?? available.first(where: {
            $0.replacingOccurrences(of: "_", with: "-").lowercased().hasPrefix(language.rawValue + "-") || $0 == language.rawValue
        }) else { return (false, []) }
        let text = word.lowercased()
        let range = NSRange(location: 0, length: (text as NSString).length)
        let misspelled = checker.rangeOfMisspelledWord(in: text, range: range, startingAt: 0, wrap: false, language: code)
        if misspelled.location == NSNotFound { return (true, []) }
        return (false, Array((checker.guesses(forWordRange: range, in: text, language: code) ?? []).prefix(8)))
    }
}

final class KeyboardViewController: UIInputViewController, UIGestureRecognizerDelegate {
    private var state = InputState()
    private let theme = KeyboardTheme.material
    private var settings = KeyboardSettings()
    private let provider: any SuggestionProvider = LocalSuggestionProvider()
    private let rows = UIStackView()
    private let keyPlane = KeyboardTouchSurface(frame: .zero)
    private var touchAdaptation = TouchCalibrationStorage.load()
    private var pendingCalibrationSamples = 0
    private let lexiconQueue = DispatchQueue(label: "GlassType.lexicon", qos: .userInitiated)
    private var glideGeneration: UInt = 0
    private var trailSamples: [(point: CGPoint, time: TimeInterval)] = []
    private var trailTimer: Timer?
    private let suggestions = UIStackView()
    private let toolbar = UIStackView()
    private var feedback: UIImpactFeedbackGenerator?
    private var settingsPanel: UIView?
    private var popupStartX: CGFloat = 0
    private var popupInitialIndex = 0
    private let keyPreview = KeyPreviewView(frame: .zero)
    private weak var previewKey: KeyButton?
    private var previewHide: DispatchWorkItem?
    private var previewGeneration: UInt = 0
    private var heightConstraint: NSLayoutConstraint?
    private weak var deleteButton: DeleteKeyButton?
    private var popup: UIView?
    private var popupValues: [String] = []
    private var popupLabels: [UILabel] = []
    private var popupIndex = 0
    private var letterButtons: [(UIButton, String)] = []
    private weak var shiftButton: UIButton?
    private weak var symbolsButton: UIButton?
    private weak var languageButton: KeyButton?
    private var settingsHintTask: DispatchWorkItem?
    private var renderedShift: String?
    private weak var spaceButton: SpacebarButton?
    private var cursorMode = false
    private var cursorDocument: String?
    private var lastWidth: CGFloat = 0
    private var lastHeight: CGFloat = 0
    private var lastLandscape = false
    private var pendingPrefix: String?
    private var suggestionWords: [String] = []
    private var suggestionSignature: String?
    private let correctionEngine = AutocorrectionEngine()
    private lazy var spelling = SystemSpelling()
    private var correctionUndo: CorrectionUndo?
    private var suppressedCorrection: String?
    private var deletionUndo: TextDeletionUndo?
    private var lastSpace: (time: TimeInterval, before: String, after: String?, document: String)?
    private enum LexiconField { case source, replacement, exception }
    private var lexiconEditing: LexiconField?
    private var draftSource = "", draftValue = ""
    private weak var draftLabel: UILabel?
    private var glideWords: [String] = []
    private var glideUndo: CorrectionUndo?
    private var glideSnapshot: (String?, String?, String?, String, KeyboardLanguage)?
    private let glideTrail = CAShapeLayer()
    private lazy var glidePan: GlideTouchRecognizer = {
        let pan = GlideTouchRecognizer(target: self, action: #selector(glideChanged(_:)))
        pan.delegate = self; pan.coordinateView = view
        pan.mayBegin = { [weak self] first, last in
            guard let self else { return false }
            let a = self.keyPlane.keyIndex(at: self.view.convert(first, to: self.keyPlane))
            let b = self.keyPlane.keyIndex(at: self.view.convert(last, to: self.keyPlane))
            guard let b, let key = self.keyPlane.recognizer?.geometry.keys[b], key.role.character?.allSatisfy(\.isLetter) == true else { return false }
            return GlideActivation.shouldBegin(start: first, current: last, startKey: a, currentKey: b)
        }
        return pan
    }()

    override func loadView() {
        // Use the system keyboard surface, rather than layering a rectangular
        // extra blur over only the extension and creating a seam at the dock.
        let keyboard = UIInputView(frame: .zero, inputViewStyle: .keyboard)
        keyboard.allowsSelfSizing = true
        keyboard.backgroundColor = .clear; keyboard.isOpaque = false
        keyboard.clipsToBounds = true
        view = keyboard
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
        inputView?.backgroundColor = .clear
        inputView?.isOpaque = false
        rows.translatesAutoresizingMaskIntoConstraints = false
        rows.axis = .vertical; rows.spacing = 0
        toolbar.heightAnchor.constraint(equalToConstant: 32).isActive = true
        view.addSubview(rows)
        rows.addGestureRecognizer(glidePan)
        keyPlane.didLayoutKey = { button, key in
            (button as? KeyButton)?.visualCapFrame = key.visualFrame.offsetBy(dx: -key.slotFrame.minX, dy: -key.slotFrame.minY)
        }
        keyPlane.canLearn = { [weak self] in self?.canLearnTouch == true }
        keyPlane.didLearn = { [weak self] x, y in self?.learnTouch(x: x, y: y) }
        glideTrail.fillColor = nil; glideTrail.lineWidth = 3; glideTrail.lineCap = .round; glideTrail.lineJoin = .round
        view.layer.addSublayer(glideTrail)
        keyPreview.isHidden = true; view.addSubview(keyPreview)
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            rows.topAnchor.constraint(equalTo: view.topAnchor, constant: 5),
            rows.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        let height = view.heightAnchor.constraint(equalToConstant: 280)
        height.priority = .init(999); height.isActive = true; heightConstraint = height
        reloadSettings()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated); reloadSettings(); updateContext()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated); flushTouchCalibration(); cancelGlide(); hideKeyPreview(); spaceButton?.cancelInteraction(); stopDeleting(); dismissPopup(); hideLocalSettings(); feedback = nil; correctionUndo = nil; suppressedCorrection = nil
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.width > 0 else { return }
        // A landscape keyboard can occupy a narrow split-screen host; use screen orientation too.
        let landscape = (view.window?.windowScene?.interfaceOrientation.isLandscape ?? false)
        let baseHeight: CGFloat = (landscape ? (settings.compactKeys ? 188 : 202) : (settings.compactKeys ? 254 : 278))
        let desired = baseHeight * 1.05 - (needsToolbar ? 0 : 32) + view.safeAreaInsets.bottom
        if heightConstraint?.constant != desired { heightConstraint?.constant = desired }
        if abs(lastWidth - view.bounds.width) > 1 || abs(lastHeight - view.bounds.height) > 1 || landscape != lastLandscape {
            lastWidth = view.bounds.width; lastHeight = view.bounds.height; lastLandscape = landscape
            applyTouchConfiguration()
            cancelGlide(); hideKeyPreview(); spaceButton?.cancelInteraction(); stopDeleting(); dismissPopup()
            for button in keyPlane.keyViews where button.isTracking { button.cancelTracking(with: nil) }
            for (button, _) in letterButtons { button.titleLabel?.font = .systemFont(ofSize: keyFontSize()) }
            symbolsButton?.titleLabel?.font = .systemFont(ofSize: keyFontSize() * 0.765)
        }
    }
    override func textDidChange(_ textInput: UITextInput?) { cancelCursorIfDocumentChanged(); invalidateSpaceSnapshot(); invalidateCorrectionUndo(); updateContext() }
    override func selectionDidChange(_ textInput: UITextInput?) { cancelCursorIfDocumentChanged(); invalidateSpaceSnapshot(); dismissPopup(); invalidateCorrectionUndo(); updateContext() }
    private func reloadSettings() {
        settings = KeyboardSettings.loadKeyboard(fullAccess: hasFullAccess)
        configureFeedback()
        state.language = KeyboardSettings.lastUsedLanguage(enabled: settings.languages)
        KeyboardSettings.rememberLanguage(state.language)
        switch settings.theme {
        case .system: overrideUserInterfaceStyle = .unspecified
        case .light: overrideUserInterfaceStyle = .light
        case .dark: overrideUserInterfaceStyle = .dark
        }
        prewarmLexicon()
        rebuild()
    }
    private func clear(_ stack: UIStackView) {
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
    }
    private func rebuild() {
        cancelGlide(); lastSpace = nil; glideWords = []; glideUndo = nil; deletionUndo = nil
        hideKeyPreview(); spaceButton?.cancelInteraction(); spaceButton = nil; symbolsButton = nil
        stopDeleting(); dismissPopup(); hideLocalSettings(); clear(rows); clear(toolbar); clear(suggestions); letterButtons.removeAll(); shiftButton = nil; renderedShift = nil
        suggestionSignature = nil; suggestionWords.removeAll(); correctionUndo = nil
        view.setNeedsLayout()
        suggestions.axis = .horizontal; suggestions.distribution = .fillEqually; suggestions.spacing = 6
        toolbar.axis = .horizontal; toolbar.spacing = 6
        toolbar.addArrangedSubview(suggestions)
        if needsToolbar { rows.addArrangedSubview(toolbar) }
        if lexiconEditing != nil { configureEditorBar() }
        for button in keyPlane.keyViews { button.removeFromSuperview() }
        keyPlane.keyViews.removeAll(keepingCapacity: true)
        keyPlane.language = state.language; keyPlane.symbolPage = state.symbols ? state.symbolPage : nil
        keyPlane.compact = settings.compactKeys; keyPlane.needsSystemKey = needsInputModeSwitchKey
        keyPlane.showsDebugZones = settings.debugTouchZones
        func attach(_ button: UIButton) {
            if let key = button as? KeyButton {
                key.touchSurface = keyPlane; key.geometryIndex = keyPlane.keyViews.count
                key.learningMaximumDuration = settings.holdDelay
            }
            keyPlane.keyViews.append(button); keyPlane.addSubview(button)
        }
        let keyRows = state.symbols ? state.symbolPage.rows : state.language.rows
        for (index, keys) in keyRows.enumerated() {
            if index == 2 {
                let shift = makeButton(state.symbols ? state.symbolPage.switchTitle : "⇧", special: true)
                shift.accessibilityLabel = state.symbols ? "Другая страница символов" : "Shift — двойное нажатие: Caps Lock"
                shift.addTarget(self, action: #selector(shiftTapped), for: .touchUpInside)
                shiftButton = shift; attach(shift)
            }
            for key in keys {
                let button = makeButton(key)
                button.accessibilityLabel = key
                button.addAction(UIAction { [weak self] _ in self?.insert(key) }, for: .touchUpInside)
                let alternatives = state.symbols ? state.language.alternatives(for: key) : state.language.holdAlternatives(for: key, symbolsEnabled: settings.extraSymbols)
                configureHold(on: button, alternatives: alternatives)
                letterButtons.append((button, key)); attach(button)
            }
            if index == 2 {
                let delete = makeButton("⌫", special: true); delete.accessibilityLabel = "Удалить"
                deleteButton = delete as? DeleteKeyButton
                deleteButton?.deleteAction = { [weak self] in self?.deleteOnce() }
                deleteButton?.deleteWordAction = { [weak self] in self?.deleteWord() }
                deleteButton?.canSwipeWord = { [weak self] in self?.settings.swipeDeleteWord == true && self?.lexiconEditing == nil }
                delete.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Удалить слово") { [weak self] _ in self?.deleteWord(); return true }]
                attach(delete)
            }
        }
        let bottomStart = keyPlane.keyViews.count
        let symbols = makeButton(state.symbols ? "ABC" : "123", special: true)
        symbolsButton = symbols
        symbols.titleLabel?.font = .systemFont(ofSize: keyFontSize() * 0.765)
        symbols.addAction(UIAction { [weak self] _ in guard let self else { return }; self.state.symbols.toggle(); if self.state.symbols { self.state.symbolPage = .numbers }; self.rebuild() }, for: .touchUpInside)
        attach(symbols)
        let language = makeButton("", special: true)
        languageButton = language as? KeyButton
        language.setImage(UIImage(systemName: "globe", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .regular)), for: .normal)
        language.tintColor = theme.foreground
        language.accessibilityLabel = "Сменить язык"; language.accessibilityValue = state.language.title
        language.accessibilityHint = "Удерживайте для настроек клавиатуры"
        language.addAction(UIAction { [weak self] _ in self?.cycleLanguage(.next) }, for: .touchUpInside)
        let settingsPress = UILongPressGestureRecognizer(target: self, action: #selector(settingsHeld(_:)))
        settingsPress.minimumPressDuration = settings.holdDelay
        settingsPress.delaysTouchesBegan = false; settingsPress.delaysTouchesEnded = false
        language.addGestureRecognizer(settingsPress)
        language.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Настройки клавиатуры") { [weak self] _ in self?.showLocalSettings(); return true },
            UIAccessibilityCustomAction(name: "Предыдущий язык") { [weak self] _ in self?.cycleLanguage(.previous); return true }
        ]
        let gearHint = UIImageView(image: UIImage(systemName: "gearshape.fill"))
        gearHint.tintColor = .secondaryLabel; gearHint.isUserInteractionEnabled = false
        gearHint.isAccessibilityElement = false; gearHint.translatesAutoresizingMaskIntoConstraints = false
        language.addSubview(gearHint)
        NSLayoutConstraint.activate([
            gearHint.widthAnchor.constraint(equalToConstant: 9), gearHint.heightAnchor.constraint(equalToConstant: 9),
            gearHint.topAnchor.constraint(equalTo: language.topAnchor, constant: 6),
            gearHint.trailingAnchor.constraint(equalTo: language.trailingAnchor, constant: -6)
        ])
        attach(language)
        if needsInputModeSwitchKey {
            // This is distinct from our language globe: iOS requires access to
            // other installed system keyboards when it does not supply a dock key.
            let systemKeyboard = makeButton("", special: true)
            systemKeyboard.setImage(UIImage(systemName: "keyboard", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18)), for: .normal)
            systemKeyboard.tintColor = theme.foreground
            systemKeyboard.accessibilityLabel = "Другие системные клавиатуры"
            systemKeyboard.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
            attach(systemKeyboard)
        }
        let comma = makeButton(","); comma.accessibilityLabel = "Запятая"
        comma.addAction(UIAction { [weak self] _ in self?.insert(",") }, for: .touchUpInside)
        attach(comma)
        let space = SpacebarButton(frame: .zero)
        configureButton(space, title: spaceTitle())
        spaceButton = space
        space.accessibilityLabel = "Пробел"; space.accessibilityValue = state.language.title
        space.accessibilityHint = "Быстрый свайп влево или вправо меняет язык. Удерживайте и двигайте палец для перемещения курсора."
        space.titleLabel?.font = .systemFont(ofSize: 14)
        space.onAction = { [weak self] action in self?.handleSpaceAction(action) }
        space.onCursorEnd = { [weak self] in self?.setCursorMode(false) }
        space.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Следующий язык") { [weak self] _ in self?.cycleLanguage(.next); return true },
            UIAccessibilityCustomAction(name: "Предыдущий язык") { [weak self] _ in self?.cycleLanguage(.previous); return true },
            UIAccessibilityCustomAction(name: "Курсор влево") { [weak self] _ in self?.moveCursor(-1); return true },
            UIAccessibilityCustomAction(name: "Курсор вправо") { [weak self] _ in self?.moveCursor(1); return true }
        ]
        attach(space)
        let punctuation = makeButton("."); punctuation.addAction(UIAction { [weak self] _ in self?.insert(".") }, for: .touchUpInside)
        configureHold(on: punctuation, alternatives: state.language.alternatives(for: "."))
        attach(punctuation)
        let enter = makeButton("", special: true)
        enter.setImage(UIImage(systemName: "return", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19.89, weight: .medium)), for: .normal)
        enter.tintColor = theme.foreground
        enter.accessibilityLabel = returnTitle()
        enter.addAction(UIAction { [weak self] _ in self?.insert("\n") }, for: .touchUpInside)
        attach(enter)
        for key in keyPlane.keyViews.dropFirst(bottomStart).compactMap({ $0 as? KeyButton }) {
            key.pressBehavior = key === space ? .spacebar : .function
        }
        rows.addArrangedSubview(keyPlane)
        keyPlane.invalidateGeometry(); applyTouchConfiguration()
        refreshLabels(); refreshSuggestions()
    }
    private func makeButton(_ title: String, special: Bool = false) -> UIButton {
        let button: KeyButton = title == "⌫" ? DeleteKeyButton(frame: .zero) : KeyButton(frame: .zero)
        configureButton(button, title: title)
        button.showsCharacterPreview = !special && title.count == 1
        button.pressBehavior = !special && title.count == 1 ? .character : .function
        return button
    }
    private func configureButton(_ button: KeyButton, title: String) {
        button.compact = settings.compactKeys
        button.keyRadius = theme.radius
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 3, bottom: 0, right: 3)
        button.setTitle(title, for: .normal); button.setTitleColor(theme.foreground, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: keyFontSize())
        button.titleLabel?.adjustsFontSizeToFitWidth = true; button.titleLabel?.minimumScaleFactor = 0.6
        button.fillColor = button is SpacebarButton ? theme.spacebar : theme.key
        button.pressBehavior = button is SpacebarButton ? .spacebar : .function
        button.addAction(UIAction { [weak self, weak button] _ in
            self?.performFeedback()
            if let button {
                if button === self?.languageButton { self?.scheduleSettingsHint(for: button) }
                else { self?.showKeyPreview(for: button) }
            }
        }, for: .touchDown)
        button.addAction(UIAction { [weak self, weak button] _ in
            if let button { self?.finishKeyPreview(for: button, immediately: false) }
        }, for: .touchUpInside)
        button.addAction(UIAction { [weak self, weak button] _ in
            if let button { self?.finishKeyPreview(for: button, immediately: true) }
        }, for: [.touchUpOutside, .touchCancel, .touchDragExit])
        button.addAction(UIAction { [weak self, weak button] _ in
            if let button { self?.showKeyPreview(for: button) }
        }, for: .touchDragEnter)
    }
    private func keyFontSize() -> CGFloat {
        lastLandscape ? (settings.compactKeys ? 18 : 19) : (settings.compactKeys ? 21 : 22)
    }
    private func showKeyPreview(for button: KeyButton) {
        guard settings.showKeyPreview, button.showsCharacterPreview,
              !cursorMode, settingsPanel == nil, !UIAccessibility.isVoiceOverRunning,
              button.window != nil, let text = button.title(for: .normal), !text.isEmpty,
              let placement = KeyPreviewLayout.make(keyFrame: button.convert(button.bounds, to: view), availableBounds: view.bounds) else { hideKeyPreview(); return }
        previewHide?.cancel(); previewHide = nil; previewGeneration &+= 1
        let wasHidden = keyPreview.isHidden
        previewKey = button
        keyPreview.layer.removeAllAnimations(); keyPreview.transform = .identity
        keyPreview.configure(layout: placement, text: text, fill: theme.key.withAlphaComponent(1), ink: theme.foreground)
        view.bringSubviewToFront(keyPreview); keyPreview.isHidden = false
        if wasHidden && !UIAccessibility.isReduceMotionEnabled {
            keyPreview.alpha = 0; keyPreview.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
            UIView.animate(withDuration: 0.07, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.keyPreview.alpha = 1; self.keyPreview.transform = .identity
            }
        } else { keyPreview.alpha = 1 }
    }
    private func finishKeyPreview(for button: KeyButton, immediately: Bool) {
        if button === languageButton { settingsHintTask?.cancel(); settingsHintTask = nil }
        guard previewKey === button else { return }
        previewHide?.cancel(); previewHide = nil
        if immediately { hideKeyPreview(); return }
        let generation = previewGeneration
        let task = DispatchWorkItem { [weak self, weak button] in
            guard let self, let button, self.previewKey === button, self.previewGeneration == generation else { return }
            self.hideKeyPreview()
        }
        previewHide = task; DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: task)
    }
    private func hideKeyPreview() {
        settingsHintTask?.cancel(); settingsHintTask = nil
        previewHide?.cancel(); previewHide = nil; previewKey = nil; previewGeneration &+= 1
        keyPreview.layer.removeAllAnimations(); keyPreview.isHidden = true
        keyPreview.alpha = 1; keyPreview.transform = .identity
    }
    private var canLearnTouch: Bool {
        settings.touchAdaptationEnabled && !state.symbols && !cursorMode && settingsPanel == nil && lexiconEditing == nil &&
        textAllowsAutomation && textDocumentProxy.autocorrectionType != .no && textDocumentProxy.spellCheckingType != .no &&
        textDocumentProxy.documentContextBeforeInput != nil && (textDocumentProxy.selectedText ?? "").isEmpty && !UIAccessibility.isVoiceOverRunning
    }
    private func applyTouchConfiguration() {
        keyPlane.setConfiguration(touchAdaptation.configuration(landscape: lastLandscape, enabled: settings.touchAdaptationEnabled))
        keyPlane.showsDebugZones = settings.debugTouchZones
    }
    private func learnTouch(x: Double, y: Double) {
        let accepted: Bool
        if lastLandscape { accepted = touchAdaptation.landscape.observe(x: x, y: y) }
        else { accepted = touchAdaptation.portrait.observe(x: x, y: y) }
        guard accepted else { return }
        pendingCalibrationSamples += 1
        if pendingCalibrationSamples >= 64 {
            flushTouchCalibration()
            // Keep a touch's decision boundary stable for its whole lifetime.
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.keyPlane.keyViews.contains(where: { $0.isTracking }) else { return }
                self.applyTouchConfiguration()
            }
        }
    }
    private func flushTouchCalibration() {
        if pendingCalibrationSamples > 0 { TouchCalibrationStorage.save(touchAdaptation); pendingCalibrationSamples = 0 }
    }
    private func resetTouchCalibration() {
        touchAdaptation = .init(); pendingCalibrationSamples = 0; TouchCalibrationStorage.reset(); applyTouchConfiguration()
    }
    private func prewarmLexicon() {
        let language = state.language
        lexiconQueue.async { GlideDecoder.prepare(language: language) }
    }
    private func configureFeedback() {
        let style: UIImpactFeedbackGenerator.FeedbackStyle
        switch settings.haptics {
        case .off: feedback = nil; return
        case .light: style = .light
        case .medium: style = .medium
        case .strong: style = .heavy
        }
        feedback = UIImpactFeedbackGenerator(style: style)
        feedback?.prepare()
    }
    private func performFeedback() {
        feedback?.impactOccurred()
        feedback?.prepare()
    }
    private func configureHold(on button: UIButton, alternatives: [String]) {
        guard !alternatives.isEmpty else { return }
        let press = UILongPressGestureRecognizer(target: self, action: #selector(alternatePress(_:)))
        press.minimumPressDuration = settings.holdDelay
        press.delaysTouchesBegan = false; press.delaysTouchesEnded = false
        button.addGestureRecognizer(press)
        button.accessibilityHint = "Удерживайте для: " + alternatives.joined(separator: ", ")
        button.accessibilityCustomActions = alternatives.map { value in
            UIAccessibilityCustomAction(name: value) { [weak self] _ in self?.performFeedback(); self?.insert(value); return true }
        }
        if settings.symbolHints, let hint = alternatives.first {
            let label = UILabel(); label.text = hint
            label.font = .systemFont(ofSize: 9, weight: .medium)
            label.textColor = .secondaryLabel; label.isUserInteractionEnabled = false
            label.isAccessibilityElement = false; label.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(label)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: button.topAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -6)
            ])
            button.titleEdgeInsets = UIEdgeInsets(top: 5, left: 0, bottom: 0, right: 0)
        }
    }
    private func hideLocalSettings() {
        settingsPanel?.removeFromSuperview(); settingsPanel = nil; rows.isHidden = false
    }
    private func showLocalSettings() {
        guard settingsPanel == nil else { return }
        lexiconEditing = nil
        cancelGlide(); hideKeyPreview(); spaceButton?.cancelInteraction(); stopDeleting(); dismissPopup()

        // Keep the native keyboard material continuous behind the settings.
        let panel = UIView(); panel.backgroundColor = .clear
        panel.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor), panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.topAnchor.constraint(equalTo: view.topAnchor), panel.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        let header = UIView(); header.backgroundColor = .clear
        header.translatesAutoresizingMaskIntoConstraints = false; panel.addSubview(header)
        let title = UILabel(); title.text = "Клавиатура"
        title.font = .preferredFont(forTextStyle: .headline); title.adjustsFontForContentSizeCategory = true
        title.adjustsFontSizeToFitWidth = true; title.minimumScaleFactor = 0.8
        title.accessibilityTraits.insert(.header)
        title.translatesAutoresizingMaskIntoConstraints = false; header.addSubview(title)
        let done = UIButton(type: .system); done.setTitle("Готово", for: .normal)
        done.titleLabel?.font = .preferredFont(forTextStyle: .body)
        done.titleLabel?.adjustsFontForContentSizeCategory = true
        done.translatesAutoresizingMaskIntoConstraints = false; header.addSubview(done)
        done.addAction(UIAction { [weak self] _ in self?.rebuild() }, for: .touchUpInside)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            header.topAnchor.constraint(equalTo: panel.topAnchor), header.heightAnchor.constraint(equalToConstant: 44),
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor), title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: done.leadingAnchor, constant: -8),
            done.trailingAnchor.constraint(equalTo: header.trailingAnchor), done.topAnchor.constraint(equalTo: header.topAnchor),
            done.bottomAnchor.constraint(equalTo: header.bottomAnchor), done.widthAnchor.constraint(greaterThanOrEqualToConstant: 68)
        ])
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true; scroll.isDirectionalLockEnabled = true
        scroll.contentInsetAdjustmentBehavior = .never
        panel.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            scroll.bottomAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.bottomAnchor)
        ])
        let content = UIStackView(); content.axis = .vertical; content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -12),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 8),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -12),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -24)
        ])
        func card(_ heading: String) -> UIStackView {
            let caption = UILabel(); caption.text = heading
            caption.font = .preferredFont(forTextStyle: .footnote); caption.textColor = .secondaryLabel
            caption.adjustsFontForContentSizeCategory = true; caption.accessibilityTraits.insert(.header)
            content.addArrangedSubview(caption)
            let surface = UIView(); surface.backgroundColor = .tertiarySystemFill
            surface.layer.cornerRadius = 13; surface.layer.cornerCurve = .continuous; surface.clipsToBounds = true
            let group = UIStackView(); group.axis = .vertical; group.spacing = 0
            group.translatesAutoresizingMaskIntoConstraints = false; surface.addSubview(group)
            NSLayoutConstraint.activate([
                group.leadingAnchor.constraint(equalTo: surface.leadingAnchor), group.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
                group.topAnchor.constraint(equalTo: surface.topAnchor), group.bottomAnchor.constraint(equalTo: surface.bottomAnchor)
            ])
            content.addArrangedSubview(surface); content.setCustomSpacing(18, after: surface)
            return group
        }
        func append(_ item: UIView, to group: UIStackView) {
            if !group.arrangedSubviews.isEmpty {
                let separator = UIView(); separator.backgroundColor = .separator
                separator.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                group.addArrangedSubview(separator)
            }
            group.addArrangedSubview(item)
        }
        func toggle(_ text: String, value: Bool, group: UIStackView, change: @escaping (Bool) -> Void) {
            let line = UIControl(); line.isAccessibilityElement = false
            line.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            let label = UILabel(); label.text = text; label.numberOfLines = 0
            label.font = .preferredFont(forTextStyle: .body); label.adjustsFontForContentSizeCategory = true
            label.isAccessibilityElement = false; label.translatesAutoresizingMaskIntoConstraints = false
            line.addSubview(label)
            // Default UISwitch styling lets the running iOS choose its own
            // thumb, track, accessibility appearance and interaction.
            let control = UISwitch(); control.isOn = value; control.accessibilityLabel = text
            control.translatesAutoresizingMaskIntoConstraints = false; line.addSubview(control)
            control.setContentCompressionResistancePriority(.required, for: .horizontal)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: line.leadingAnchor, constant: 12),
                label.topAnchor.constraint(equalTo: line.topAnchor, constant: 10),
                label.bottomAnchor.constraint(equalTo: line.bottomAnchor, constant: -10),
                label.trailingAnchor.constraint(equalTo: control.leadingAnchor, constant: -12),
                control.trailingAnchor.constraint(equalTo: line.trailingAnchor, constant: -12),
                control.centerYAnchor.constraint(equalTo: line.centerYAnchor)
            ])
            control.addAction(UIAction { [weak control] _ in
                if let control { change(control.isOn) }
            }, for: .valueChanged)
            // Tapping the label also toggles; direct switch drags remain native.
            line.addAction(UIAction { [weak control] _ in
                guard let control else { return }
                control.setOn(!control.isOn, animated: true); control.sendActions(for: .valueChanged)
            }, for: .touchUpInside)
            append(line, to: group)
        }
        func segmented(_ text: String, control: UISegmentedControl, group: UIStackView) {
            let container = UIView()
            let label = UILabel(); label.text = text; label.numberOfLines = 0
            label.font = .preferredFont(forTextStyle: .body); label.adjustsFontForContentSizeCategory = true
            label.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(label)
            control.accessibilityLabel = text; control.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(control)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
                label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
                label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
                control.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
                control.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
                control.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
                control.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
                control.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
            ])
            append(container, to: group)
        }

        let typing = card("Ввод")
        toggle("Автозамена", value: settings.autoCorrection, group: typing) { [weak self] value in
            self?.settings.autoCorrection = value; self?.settings.saveKeyboardOverrides()
        }
        toggle("Заглавные в начале предложений", value: settings.autoCapitalization, group: typing) { [weak self] value in
            self?.settings.autoCapitalization = value; self?.settings.saveKeyboardOverrides()
        }
        toggle("Двойной пробел → точка", value: settings.doubleSpacePeriod, group: typing) { [weak self] value in
            self?.settings.doubleSpacePeriod = value; self?.settings.saveKeyboardOverrides()
        }
        toggle("Свайп удаления слова", value: settings.swipeDeleteWord, group: typing) { [weak self] value in
            self?.settings.swipeDeleteWord = value; self?.settings.saveKeyboardOverrides()
        }
        toggle("Свайп-ввод слов · эксперимент", value: settings.glideTyping, group: typing) { [weak self] value in
            self?.settings.glideTyping = value; self?.settings.saveKeyboardOverrides()
        }
        let feedbackCard = card("Тактильный отклик")
        let haptics = UISegmentedControl(items: HapticChoice.allCases.map(\.title))
        haptics.selectedSegmentIndex = HapticChoice.allCases.firstIndex(of: settings.haptics) ?? 0
        haptics.addAction(UIAction { [weak self, weak haptics] _ in
            guard let self, let haptics, HapticChoice.allCases.indices.contains(haptics.selectedSegmentIndex) else { return }
            self.settings.haptics = HapticChoice.allCases[haptics.selectedSegmentIndex]
            self.settings.saveKeyboardOverrides(); self.configureFeedback(); self.performFeedback()
        }, for: .valueChanged)
        segmented("Сила виброотклика", control: haptics, group: feedbackCard)

        let symbols = card("Дополнительные символы")
        toggle("Символы удержанием", value: settings.extraSymbols, group: symbols) { [weak self] value in
            self?.settings.extraSymbols = value; self?.settings.saveKeyboardOverrides()
        }
        toggle("Метки на клавишах", value: settings.symbolHints, group: symbols) { [weak self] value in
            self?.settings.symbolHints = value; self?.settings.saveKeyboardOverrides()
        }
        let delay = UISegmentedControl(items: ["0,25 с", "0,4 с", "0,6 с"])
        delay.selectedSegmentIndex = settings.holdDelay < 0.325 ? 0 : (settings.holdDelay < 0.5 ? 1 : 2)
        delay.addAction(UIAction { [weak self, weak delay] _ in
            guard let self, let delay, (0...2).contains(delay.selectedSegmentIndex) else { return }
            self.settings.holdDelay = [0.25, 0.4, 0.6][delay.selectedSegmentIndex]; self.settings.saveKeyboardOverrides()
        }, for: .valueChanged)
        segmented("Задержка удержания", control: delay, group: symbols)

        let appearance = card("Внешний вид")
        toggle("Компактные клавиши", value: settings.compactKeys, group: appearance) { [weak self] value in
            self?.settings.compactKeys = value; self?.settings.saveKeyboardOverrides()
        }
        toggle("Отображение символа при нажатии", value: settings.showKeyPreview, group: appearance) { [weak self] value in
            guard let self else { return }
            self.settings.showKeyPreview = value; self.settings.saveKeyboardOverrides()
            if !value { self.hideKeyPreview() }
        }
        let accuracy = card("Точность касаний")
        toggle("Адаптация касаний", value: settings.touchAdaptationEnabled, group: accuracy) { [weak self] value in
            guard let self else { return }
            self.settings.touchAdaptationEnabled = value; self.settings.saveKeyboardOverrides(); self.applyTouchConfiguration()
        }
        toggle("Показать зоны касаний", value: settings.debugTouchZones, group: accuracy) { [weak self] value in
            self?.settings.debugTouchZones = value; self?.settings.saveKeyboardOverrides(); self?.applyTouchConfiguration()
        }
        let calibrationNote = UILabel(); calibrationNote.numberOfLines = 0
        calibrationNote.font = .preferredFont(forTextStyle: .footnote); calibrationNote.textColor = .secondaryLabel
        calibrationNote.text = "Только обезличенные средние смещения и разброс. Буквы, сообщения, пароли и история координат не сохраняются. Сброс — отдельно для всех ориентаций."
        content.addArrangedSubview(calibrationNote)
        let clearCalibration = UIButton(type: .system); clearCalibration.setTitle("Сбросить адаптацию касаний", for: .normal)
        clearCalibration.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        clearCalibration.addAction(UIAction { [weak self, weak clearCalibration] _ in
            self?.resetTouchCalibration(); clearCalibration?.setTitle("Адаптация сброшена", for: .normal)
        }, for: .touchUpInside)
        append(clearCalibration, to: accuracy)
        let dictionaryCard = card("Личный словарь")
        let dictionary = UIButton(type: .system)
        var dictionaryStyle = UIButton.Configuration.plain()
        dictionaryStyle.title = "Замены и исключения"
        dictionaryStyle.image = UIImage(systemName: "chevron.forward")
        dictionaryStyle.imagePlacement = .trailing; dictionaryStyle.imagePadding = 8
        dictionaryStyle.baseForegroundColor = .label
        dictionaryStyle.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        dictionary.configuration = dictionaryStyle; dictionary.contentHorizontalAlignment = .leading
        dictionary.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        dictionary.addAction(UIAction { [weak self] _ in self?.showLexiconPanel() }, for: .touchUpInside)
        append(dictionary, to: dictionaryCard)

        let note = UILabel(); note.numberOfLines = 0
        note.font = .preferredFont(forTextStyle: .footnote); note.adjustsFontForContentSizeCategory = true
        note.textColor = .secondaryLabel
        note.text = "Изменения сохраняются сразу. «Готово» применяет оформление. Если вибрации нет, проверьте полный доступ и системные настройки тактильных сигналов."
        content.addArrangedSubview(note)
        let reset = UIButton(type: .system)
        var resetStyle = UIButton.Configuration.plain()
        resetStyle.title = "Сбросить локальные настройки"; resetStyle.baseForegroundColor = .systemRed
        resetStyle.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)
        reset.configuration = resetStyle; reset.titleLabel?.numberOfLines = 0
        reset.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        reset.addAction(UIAction { [weak self] _ in
            KeyboardSettings.clearKeyboardOverrides(); self?.reloadSettings()
        }, for: .touchUpInside)
        content.addArrangedSubview(reset)
        let preservation = UILabel(); preservation.text = "Личный словарь при сбросе сохранится."
        preservation.numberOfLines = 0; preservation.textColor = .secondaryLabel
        preservation.font = .preferredFont(forTextStyle: .footnote); preservation.adjustsFontForContentSizeCategory = true
        content.addArrangedSubview(preservation)

        rows.isHidden = true; settingsPanel = panel
        UIAccessibility.post(notification: .screenChanged, argument: done)
    }

    private func spaceTitle() -> String { "‹ " + state.language.title + " ›" }
    @objc private func settingsHeld(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { performFeedback(); showLocalSettings() }
    }
    private func handleSpaceAction(_ action: SpacebarInteraction.Action) {
        switch action {
        case .none: break
        case .insertSpace: if !cursorMode && settingsPanel == nil { insert(" ") }
        case .changeLanguage(let direction): cycleLanguage(direction)
        case .cursorBegan:
            if lexiconEditing != nil { spaceButton?.cancelInteraction() } else { setCursorMode(true) }
        case .moveCursor(let offset): moveCursor(offset)
        }
    }
    private func cycleLanguage(_ direction: LanguageDirection) {
        guard !cursorMode, settingsPanel == nil, settings.languages.count > 1 else { return }
        state.cycleLanguage(enabled: settings.languages, direction: direction)
        KeyboardSettings.rememberLanguage(state.language)
        prewarmLexicon()
        suppressedCorrection = nil; performFeedback(); rebuild()
    }
    private func setCursorMode(_ active: Bool) {
        guard cursorMode != active else { return }
        cancelGlide(); hideKeyPreview(); cursorMode = active
        correctionUndo = nil; suppressedCorrection = nil; deletionUndo = nil; lastSpace = nil; glideWords = []; glideUndo = nil
        cursorDocument = active ? String(describing: textDocumentProxy.documentIdentifier) : nil
        func update(_ container: UIView) {
            for child in container.subviews {
                if let button = child as? KeyButton {
                    button.isUserInteractionEnabled = !active || button === self.spaceButton
                    button.setTrackpadAppearance(active && button !== self.spaceButton)
                } else { update(child) }
            }
        }
        update(rows)
        spaceButton?.setTitle(active ? "↔" : spaceTitle(), for: .normal)
        spaceButton?.accessibilityValue = active ? "Управление курсором" : state.language.title
        if active { dismissPopup(); stopDeleting(); performFeedback() }
        else { updateContext() }
    }
    private func cancelCursorIfDocumentChanged() {
        if cursorMode && cursorDocument != String(describing: textDocumentProxy.documentIdentifier) {
            spaceButton?.cancelInteraction()
        }
    }
    private func moveCursor(_ requested: Int) {
        guard settingsPanel == nil, lexiconEditing == nil else { return }
        if cursorMode && cursorDocument != String(describing: textDocumentProxy.documentIdentifier) {
            spaceButton?.cancelInteraction(); return
        }
        correctionUndo = nil; suppressedCorrection = nil
        let steps = min(32, max(-32, requested))
        // Let the host handle character boundaries and document edges; no UTF-16
        // slicing or document rewriting is involved in moving the caret.
        if steps != 0 {
            let document = String(describing: textDocumentProxy.documentIdentifier)
            for _ in 0..<abs(steps) {
                guard String(describing: textDocumentProxy.documentIdentifier) == document else { spaceButton?.cancelInteraction(); break }
                textDocumentProxy.adjustTextPosition(byCharacterOffset: steps < 0 ? -1 : 1)
            }
        }
        if !cursorMode { updateContext() }
    }
    private var needsToolbar: Bool { settings.suggestions || settings.showKeyPreview || settings.swipeDeleteWord || settings.glideTyping || lexiconEditing != nil }
    private func scheduleSettingsHint(for button: KeyButton) {
        hideKeyPreview()
        let task = DispatchWorkItem { [weak self, weak button] in
            guard let self, let button, self.settingsPanel == nil, !self.cursorMode,
                  let layout = KeyPreviewLayout.make(keyFrame: button.convert(button.bounds, to: self.view), availableBounds: self.view.bounds) else { return }
            self.previewGeneration &+= 1; self.previewKey = button
            self.keyPreview.configureSymbol(layout: layout, name: "gearshape.fill", fill: self.theme.key.withAlphaComponent(1), ink: self.theme.foreground)
            self.keyPreview.alpha = 1; self.keyPreview.transform = .identity
            self.keyPreview.isHidden = false; self.view.bringSubviewToFront(self.keyPreview)
        }
        settingsHintTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.08, settings.holdDelay - 0.12), execute: task)
    }
    private func deleteWord() {
        glideGeneration &+= 1
        guard settings.swipeDeleteWord, lexiconEditing == nil, !cursorMode else { return }
        lastSpace = nil; correctionUndo = nil; glideWords = []; glideUndo = nil
        guard (textDocumentProxy.selectedText ?? "").isEmpty else { return }
        guard let before = textDocumentProxy.documentContextBeforeInput, !before.isEmpty, before.last?.isNewline != true else { return }
        let document = String(describing: textDocumentProxy.documentIdentifier)
        let after = textDocumentProxy.documentContextAfterInput
        var deleted = "", latest = before, stage = 0, reachedBoundary = false
        let wordLike: (Character) -> Bool = { $0.isLetter || $0.isNumber || "'’ʼ_".contains($0) }
        // Re-reading the window after each character reveals a truncated left
        // edge. Empty string is a boundary; nil is unavailable, never a boundary.
        for _ in 0..<128 {
            guard String(describing: textDocumentProxy.documentIdentifier) == document,
                  textDocumentProxy.documentContextAfterInput == after,
                  (textDocumentProxy.selectedText ?? "").isEmpty,
                  let context = textDocumentProxy.documentContextBeforeInput else { break }
            latest = context
            guard let c = context.last else { reachedBoundary = true; break }
            if c.isNewline { reachedBoundary = true; break }
            if stage == 0 && !c.isWhitespace { stage = 1 }
            if stage == 1 && wordLike(c) { stage = 2 }
            if (stage > 0 && c.isWhitespace) || (stage == 2 && !wordLike(c)) { reachedBoundary = true; break }
            deleted = String(c) + deleted
            textDocumentProxy.deleteBackward()
            latest = textDocumentProxy.documentContextBeforeInput ?? latest
        }
        guard !deleted.isEmpty, String(describing: textDocumentProxy.documentIdentifier) == document,
              textDocumentProxy.documentContextAfterInput == after, (textDocumentProxy.selectedText ?? "").isEmpty,
              let remaining = textDocumentProxy.documentContextBeforeInput, remaining == latest else { return }
        if !reachedBoundary && deleted.count >= 128 {
            textDocumentProxy.insertText(deleted); updateContext(); return
        }
        deletionUndo = TextDeletionUndo(deletedText: deleted, before: remaining, after: after, document: document)
        performFeedback(); suggestionSignature = nil; updateContext()
    }
    private func restoreDeletedWord() {
        guard let undo = deletionUndo,
              undo.matches(before: textDocumentProxy.documentContextBeforeInput, after: textDocumentProxy.documentContextAfterInput, document: String(describing: textDocumentProxy.documentIdentifier), hasSelection: !(textDocumentProxy.selectedText ?? "").isEmpty) else { deletionUndo = nil; updateContext(); return }
        deletionUndo = nil; textDocumentProxy.insertText(undo.deletedText)
        lastSpace = nil; suggestionSignature = nil; updateContext()
    }
    private var currentDraft: String { lexiconEditing == .replacement ? draftValue : draftSource }
    private var editorPrompt: String {
        switch lexiconEditing { case .source: return "Сокращение: "; case .replacement: return "Замена: "; case .exception: return "Не исправлять: "; case nil: return "" }
    }
    private func configureEditorBar() {
        clear(toolbar)
        let cancel = UIButton(type: .system); cancel.setTitle("✕", for: .normal); cancel.tintColor = theme.foreground
        cancel.addAction(UIAction { [weak self] _ in self?.finishLexiconEditing(cancelled: true) }, for: .touchUpInside)
        let label = UILabel(); label.font = .systemFont(ofSize: 13); label.textColor = theme.foreground
        label.text = editorPrompt + currentDraft + "▏"; label.lineBreakMode = .byTruncatingHead; draftLabel = label
        let done = UIButton(type: .system); done.setTitle(lexiconEditing == .source ? "Далее" : "✓", for: .normal); done.tintColor = theme.foreground
        done.addAction(UIAction { [weak self] _ in self?.finishLexiconEditing(cancelled: false) }, for: .touchUpInside)
        toolbar.addArrangedSubview(cancel); toolbar.addArrangedSubview(label); toolbar.addArrangedSubview(done)
        cancel.widthAnchor.constraint(equalToConstant: 30).isActive = true
        done.widthAnchor.constraint(equalToConstant: 56).isActive = true
    }
    private func editLexicon(_ text: String) {
        if text == "\n" { finishLexiconEditing(cancelled: false); return }
        let entered = state.inserted(text)
        if lexiconEditing == .replacement { draftValue = String((draftValue + entered).prefix(96)) }
        else { draftSource = String((draftSource + entered).prefix(32)) }
        updateContext()
    }
    private func editLexiconDelete() {
        if lexiconEditing == .replacement { if !draftValue.isEmpty { draftValue.removeLast() } }
        else if !draftSource.isEmpty { draftSource.removeLast() }
        updateContext()
    }
    private func beginLexiconEditing(_ field: LexiconField) {
        hideLocalSettings(); draftSource = ""; draftValue = ""; lexiconEditing = field
        state.symbols = false; rebuild(); updateContext()
    }
    private func finishLexiconEditing(cancelled: Bool) {
        if !cancelled {
            let source = draftSource.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty, source.allSatisfy({ $0.isLetter }) else { draftLabel?.text = "Введите одно слово буквами"; return }
            if lexiconEditing == .source { lexiconEditing = .replacement; rebuild(); updateContext(); return }
            if lexiconEditing == .exception { settings.personalLexicon.excludedWords.append(source) }
            else {
                let value = draftValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { draftLabel?.text = "Введите замену"; return }
                settings.personalLexicon.replacements[source.lowercased()] = value
            }
            settings.personalLexicon = settings.personalLexicon.sanitized(); settings.saveKeyboardOverrides()
        }
        lexiconEditing = nil; rebuild(); updateContext(); showLexiconPanel()
    }
    private func showLexiconPanel() {
        cancelGlide(); hideLocalSettings(); hideKeyPreview(); spaceButton?.cancelInteraction(); stopDeleting()
        let panel = UIView(); panel.backgroundColor = .clear; panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel); settingsPanel = panel; rows.isHidden = true
        NSLayoutConstraint.activate([panel.leadingAnchor.constraint(equalTo: view.leadingAnchor), panel.trailingAnchor.constraint(equalTo: view.trailingAnchor), panel.topAnchor.constraint(equalTo: view.topAnchor), panel.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false; panel.addSubview(scroll)
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.trailingAnchor), scroll.topAnchor.constraint(equalTo: panel.topAnchor), scroll.bottomAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.bottomAnchor)])
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 10; stack.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 12), stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -12), stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 8), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -12), stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -24)])
        func action(_ title: String, _ handler: @escaping () -> Void) {
            let button = UIButton(type: .system); button.setTitle(title, for: .normal); button.tintColor = theme.foreground
            button.titleLabel?.numberOfLines = 2; button.titleLabel?.font = .systemFont(ofSize: 14)
            button.addAction(UIAction { _ in handler() }, for: .touchUpInside); stack.addArrangedSubview(button)
        }
        action("Готово") { [weak self] in self?.rebuild(); self?.updateContext() }
        action("＋ Добавить замену") { [weak self] in self?.beginLexiconEditing(.source) }
        action("＋ Не исправлять слово") { [weak self] in self?.beginLexiconEditing(.exception) }
        let note = UILabel(); note.numberOfLines = 0; note.font = .systemFont(ofSize: 12); note.textColor = .secondaryLabel
        note.text = "Записи хранятся только на устройстве. При добавлении используйте клавиши ниже; текст в приложении не изменяется. Нажмите запись для удаления."
        stack.addArrangedSubview(note)
        for (source, target) in settings.personalLexicon.replacements.sorted(by: { $0.key < $1.key }) {
            action("\(source) → \(target)   ×") { [weak self] in self?.settings.personalLexicon.replacements.removeValue(forKey: source); self?.settings.saveKeyboardOverrides(); self?.showLexiconPanel() }
        }
        for word in settings.personalLexicon.excludedWords.sorted() {
            action("Не исправлять: \(word)   ×") { [weak self] in self?.settings.personalLexicon.excludedWords.removeAll { $0 == word }; self?.settings.saveKeyboardOverrides(); self?.showLexiconPanel() }
        }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === glidePan, settings.glideTyping, !state.symbols, !cursorMode, settingsPanel == nil, lexiconEditing == nil, textAllowsAutomation else { return false }
        var target = touch.view
        while let candidate = target {
            if letterButtons.contains(where: { $0.0 === candidate }) { return true }
            target = candidate.superview
        }
        return false
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === glidePan else { return true }
        return settings.glideTyping && !state.symbols && !cursorMode && settingsPanel == nil && lexiconEditing == nil && textAllowsAutomation
    }
    @objc private func glideChanged(_ pan: GlideTouchRecognizer) {
        switch pan.state {
        case .began:
            hideKeyPreview(); dismissPopup(); stopDeleting(); lastSpace = nil; deletionUndo = nil
            glideGeneration &+= 1
            glideSnapshot = (textDocumentProxy.documentContextBeforeInput, textDocumentProxy.documentContextAfterInput, textDocumentProxy.selectedText, String(describing: textDocumentProxy.documentIdentifier), state.language)
            trailSamples.removeAll(keepingCapacity: true)
            appendTrailPoint(pan.points.last ?? pan.startPoint)
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.drawGlide() }
            trailTimer?.invalidate(); trailTimer = timer; RunLoop.main.add(timer, forMode: .common)
        case .changed:
            if let point = pan.points.last { appendTrailPoint(point) }
        case .ended:
            guard settings.glideTyping, !state.symbols, !cursorMode, settingsPanel == nil, lexiconEditing == nil, textAllowsAutomation,
                  let snapshot = glideSnapshot, glideSnapshotMatches(snapshot) else { cancelGlide(); return }
            let points = pan.points
            var centers: [String: CGPoint] = [:]
            if let geometry = keyPlane.recognizer?.geometry {
                for key in geometry.keys {
                    if let letter = key.role.character, letter.allSatisfy(\.isLetter) {
                        centers[letter] = keyPlane.convert(key.center, to: view)
                    }
                }
            }
            let lexicon = settings.personalLexicon
            // Replacement sources are misspellings/shortcuts, not valid words.
            let extras = Array(lexicon.replacements.values) + lexicon.excludedWords
            cancelGlide()
            let generation = glideGeneration
            let capturedCenters = centers
            lexiconQueue.async { [weak self] in
                let decoded = GlideDecoder().decode(points: points, keyCenters: capturedCenters, language: snapshot.4, extraWords: extras)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.glideGeneration == generation, self.view.window != nil,
                          self.settings.glideTyping, !self.state.symbols, !self.cursorMode, self.settingsPanel == nil,
                          self.lexiconEditing == nil, self.textAllowsAutomation, self.glideSnapshotMatches(snapshot) else { return }
                    self.commitGlide(decoded, snapshot: snapshot)
                }
            }
        case .cancelled, .failed: cancelGlide()
        default: break
        }
    }
    private func glideSnapshotMatches(_ snapshot: (String?, String?, String?, String, KeyboardLanguage)) -> Bool {
        snapshot.0 != nil && snapshot.0 == textDocumentProxy.documentContextBeforeInput && snapshot.1 == textDocumentProxy.documentContextAfterInput &&
        (snapshot.2 ?? "").isEmpty && (textDocumentProxy.selectedText ?? "").isEmpty &&
        snapshot.3 == String(describing: textDocumentProxy.documentIdentifier) && snapshot.4 == state.language
    }
    private func commitGlide(_ decoded: [String], snapshot: (String?, String?, String?, String, KeyboardLanguage)) {
        guard let best = decoded.first else {
            clear(suggestions); suggestionSignature = "glide-miss"
            let label = UILabel(); label.text = "Нет совпадений"; label.textColor = .secondaryLabel
            label.textAlignment = .center; label.font = .systemFont(ofSize: 13); suggestions.addArrangedSubview(label)
            return
        }
        let inserted = state.inserted(best)
        let prefix = snapshot.0?.last.map({ $0.isLetter || $0.isNumber }) == true ? " " : ""
        correctionUndo = nil; suppressedCorrection = nil
        textDocumentProxy.insertText(prefix + inserted + " ")
        glideWords = decoded.map { word in inserted == inserted.uppercased() ? word.uppercased() : (inserted.first?.isUppercase == true ? word.capitalized : word) }
        if let before = textDocumentProxy.documentContextBeforeInput {
            glideUndo = CorrectionUndo(original: "", replacement: inserted, delimiter: " ", before: before, after: textDocumentProxy.documentContextAfterInput, document: String(describing: textDocumentProxy.documentIdentifier))
        }
        suggestionSignature = nil; performFeedback(); updateContext()
    }
    private func appendTrailPoint(_ point: CGPoint) {
        trailSamples.append((point, ProcessInfo.processInfo.systemUptime))
        if trailSamples.count > 48 { trailSamples.removeFirst(trailSamples.count - 48) }
        drawGlide()
    }
    private func drawGlide() {
        let cutoff = ProcessInfo.processInfo.systemUptime - 0.14
        trailSamples.removeAll { $0.time < cutoff }
        let path = UIBezierPath()
        if let first = trailSamples.first { path.move(to: first.point); for sample in trailSamples.dropFirst() { path.addLine(to: sample.point) } }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        glideTrail.frame = view.bounds; glideTrail.strokeColor = theme.foreground.withAlphaComponent(0.42).cgColor; glideTrail.path = path.cgPath
        CATransaction.commit()
    }
    private func cancelGlide() {
        glideGeneration &+= 1
        glidePan.cancelCurrentTouch()
        glideSnapshot = nil
        trailTimer?.invalidate(); trailTimer = nil; trailSamples.removeAll(keepingCapacity: true); glideTrail.path = nil
    }
    private func acceptGlide(_ index: Int) {
        guard glideWords.indices.contains(index), let undo = glideUndo, undoMatches(undo) else { glideWords = []; glideUndo = nil; updateContext(); return }
        let word = glideWords[index]
        for _ in (undo.replacement + " ") { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(word + " ")
        if let before = textDocumentProxy.documentContextBeforeInput {
            glideUndo = CorrectionUndo(original: "", replacement: word, delimiter: " ", before: before, after: textDocumentProxy.documentContextAfterInput, document: String(describing: textDocumentProxy.documentIdentifier))
        }
        suggestionSignature = nil; updateContext()
    }
    private func returnTitle() -> String {
        switch textDocumentProxy.returnKeyType ?? .default {
        case .go: return "Go"
        case .search: return "Поиск"
        case .send: return "Отпр."
        case .done: return "Готово"
        case .next: return "Далее"
        default: return "Ввод"
        }
    }
    private func insert(_ text: String) {
        glideGeneration &+= 1
        if lexiconEditing != nil { editLexicon(text); return }
        deletionUndo = nil; glideWords = []; glideUndo = nil
        if text == " ", settings.doubleSpacePeriod, let last = lastSpace,
           last.document == String(describing: textDocumentProxy.documentIdentifier),
           (textDocumentProxy.selectedText ?? "").isEmpty,
           let context = textDocumentProxy.documentContextBeforeInput, context == last.before, textDocumentProxy.documentContextAfterInput == last.after,
           textAllowsAutomation,
           let replacement = SmartDoubleSpace.replacement(contextBeforeInput: context, elapsedSincePreviousSpace: ProcessInfo.processInfo.systemUptime - last.time) {
            textDocumentProxy.deleteBackward(); textDocumentProxy.insertText(replacement)
            lastSpace = nil; correctionUndo = nil; updateContext(); return
        }
        lastSpace = nil
        if [" ", "\n", ".", ",", "!", "?", ":", ";"].contains(text), applyCorrection(delimiter: text) {
            if text == " " { rememberSpace() }
            updateContext(); return
        }
        correctionUndo = nil
        if text.contains(where: { $0.isLetter }) { suppressedCorrection = nil }
        textDocumentProxy.insertText(state.inserted(text))
        if text == " " { rememberSpace() }
        updateContext()
    }
    private var textAllowsAutomation: Bool {
        let type = textDocumentProxy.keyboardType ?? .default
        return textDocumentProxy.isSecureTextEntry != true && ![UIKeyboardType.URL, .emailAddress, .numberPad, .decimalPad, .phonePad, .namePhonePad, .asciiCapableNumberPad].contains(type)
    }
    private func invalidateSpaceSnapshot() {
        guard let last = lastSpace else { return }
        if last.document != String(describing: textDocumentProxy.documentIdentifier) || last.before != textDocumentProxy.documentContextBeforeInput || last.after != textDocumentProxy.documentContextAfterInput || !(textDocumentProxy.selectedText ?? "").isEmpty { lastSpace = nil }
    }
    private func rememberSpace() {
        if let context = textDocumentProxy.documentContextBeforeInput {
            lastSpace = (ProcessInfo.processInfo.systemUptime, context, textDocumentProxy.documentContextAfterInput, String(describing: textDocumentProxy.documentIdentifier))
        }
    }
    private func personalWord(in context: String) -> String? {
        guard context.last?.isLetter == true, let token = context.split(whereSeparator: { $0.isWhitespace }).last else { return nil }
        let word = String(token.reversed().prefix(while: { $0.isLetter }).reversed())
        guard (1...32).contains(word.count), token.dropLast(word.count).allSatisfy({ "([{«“\"".contains($0) }) else { return nil }
        return word
    }
    private func applyCorrection(delimiter: String) -> Bool {
        guard settings.autoCorrection, textAllowsAutomation, (textDocumentProxy.selectedText ?? "").isEmpty,
              textDocumentProxy.autocorrectionType != .no, textDocumentProxy.spellCheckingType != .no,
              let context = textDocumentProxy.documentContextBeforeInput,
              let word = personalWord(in: context) else { return false }
        let type = textDocumentProxy.keyboardType ?? .default
        guard ![UIKeyboardType.URL, .emailAddress, .numberPad, .decimalPad, .phonePad, .namePhonePad, .asciiCapableNumberPad].contains(type) else { return false }
        if suppressedCorrection == word || settings.personalLexicon.excludes(word) { return false }
        let replacement: String
        if let personal = settings.personalLexicon.replacement(for: word) { replacement = personal }
        else {
            if let explicit = correctionEngine.replacement(for: word, language: state.language) { replacement = explicit }
            else {
                let checked = spelling.check(word, language: state.language)
                let known = checked.known || OfflineLexicon.contains(word, language: state.language)
                let offline = known ? [] : OfflineLexicon.correctionCandidates(for: word, language: state.language)
                let candidates = Array(Set(offline + checked.candidates)).sorted()
                guard let candidate = correctionEngine.replacement(for: word, language: state.language, candidates: candidates, isKnownWord: known) else { return false }
                replacement = candidate
            }
        }
        guard textDocumentProxy.documentContextBeforeInput == context, (textDocumentProxy.selectedText ?? "").isEmpty else { return false }
        correctionUndo = nil
        for _ in word { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(replacement + delimiter)
        _ = state.inserted(delimiter)
        if let before = textDocumentProxy.documentContextBeforeInput, before.hasSuffix(replacement + delimiter) {
            correctionUndo = CorrectionUndo(original: word, replacement: replacement, delimiter: delimiter,
                                            before: before, after: textDocumentProxy.documentContextAfterInput,
                                            document: String(describing: textDocumentProxy.documentIdentifier))
        }
        return true
    }
    private func undoMatches(_ undo: CorrectionUndo) -> Bool {
        undo.matches(before: textDocumentProxy.documentContextBeforeInput, after: textDocumentProxy.documentContextAfterInput,
                     document: String(describing: textDocumentProxy.documentIdentifier),
                     hasSelection: !(textDocumentProxy.selectedText ?? "").isEmpty)
    }
    private func invalidateCorrectionUndo() {
        if let undo = correctionUndo, !undoMatches(undo) { correctionUndo = nil }
    }
    @objc private func shiftTapped() {
        glideGeneration &+= 1
        if state.symbols { state.symbolPage = state.symbolPage.next; rebuild(); return }
        state.tapShift(at: ProcessInfo.processInfo.systemUptime); refreshLabels()
    }
    private func refreshLabels() {
        for (button, key) in letterButtons {
            let value = state.symbols || state.shift == .off ? key : key.uppercased()
            if button.title(for: .normal) != value { button.setTitle(value, for: .normal); button.accessibilityLabel = value }
        }
        if state.symbols {
            let identity = "page:" + state.symbolPage.switchTitle
            if renderedShift != identity {
                shiftButton?.setImage(nil, for: .normal)
                shiftButton?.setTitle(state.symbolPage.switchTitle, for: .normal)
                renderedShift = identity
            }
        } else {
            let symbol = state.shift == .off ? "shift" : (state.shift == .locked ? "capslock.fill" : "shift.fill")
            if renderedShift != symbol {
                shiftButton?.setTitle(nil, for: .normal)
                shiftButton?.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)), for: .normal)
                renderedShift = symbol
            }
        }
        (shiftButton as? KeyButton)?.fillColor = theme.key
        shiftButton?.tintColor = theme.foreground
        shiftButton?.setTitleColor(theme.foreground, for: .normal)
        shiftButton?.accessibilityValue = state.symbols ? (state.symbolPage == .numbers ? "123" : "#*=") : (state.shift == .locked ? "Caps Lock" : (state.shift == .once ? "Включён" : "Выключен"))
    }
    private func stopDeleting() { deleteButton?.cancelInteraction() }
    private func deleteOnce() {
        glideGeneration &+= 1
        lastSpace = nil; deletionUndo = nil; glideWords = []; glideUndo = nil
        if lexiconEditing != nil { editLexiconDelete(); return }
        if let undo = correctionUndo, undoMatches(undo) {
            correctionUndo = nil
            for _ in (undo.replacement + undo.delimiter) { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(undo.original)
            suppressedCorrection = undo.original
        } else {
            correctionUndo = nil; suppressedCorrection = nil
            textDocumentProxy.deleteBackward()
        }
        updateContext()
    }
    private func updateContext() {
        guard !cursorMode else { return }
        if lexiconEditing != nil {
            state.synchronize(context: currentDraft, autoCapitalization: true)
            draftLabel?.text = editorPrompt + currentDraft + "▏"
            refreshLabels(); return
        }
        state.synchronize(context: textDocumentProxy.documentContextBeforeInput, autoCapitalization: settings.autoCapitalization && textAllowsAutomation)
        refreshLabels(); refreshSuggestions()
    }
    private func refreshSuggestions() {
        guard lexiconEditing == nil else { return }
        if let undo = deletionUndo, undo.matches(before: textDocumentProxy.documentContextBeforeInput, after: textDocumentProxy.documentContextAfterInput, document: String(describing: textDocumentProxy.documentIdentifier), hasSelection: !(textDocumentProxy.selectedText ?? "").isEmpty) {
            if suggestionSignature != "undo-delete" {
                clear(suggestions); suggestionSignature = "undo-delete"
                let button = makeButton("Вернуть слово", special: true); button.titleLabel?.font = .systemFont(ofSize: 14)
                button.addAction(UIAction { [weak self] _ in self?.restoreDeletedWord() }, for: .touchUpInside); suggestions.addArrangedSubview(button)
            }
            return
        }
        if !glideWords.isEmpty, let undo = glideUndo, undoMatches(undo) {
            let signature = "glide:" + glideWords.joined(separator: "|")
            if suggestionSignature != signature {
                clear(suggestions); suggestionSignature = signature
                for (index, word) in glideWords.enumerated() {
                    let button = makeButton(word, special: true); button.titleLabel?.font = .systemFont(ofSize: 15)
                    button.addAction(UIAction { [weak self] _ in self?.acceptGlide(index) }, for: .touchUpInside); suggestions.addArrangedSubview(button)
                }
            }
            return
        }
        let context = textDocumentProxy.documentContextBeforeInput
        let prefix = context.map { LocalSuggestionProvider.trailingWord(in: String($0.suffix(64))) } ?? ""
        let candidates = settings.suggestions && !prefix.isEmpty && prefix.count < 64 ? provider.suggestions(context: context ?? "", language: state.language) : []
        let words = candidates.map { candidate in
            prefix.first?.isUppercase == true ? (prefix.allSatisfy(\.isUppercase) && prefix.count > 1 ? candidate.uppercased() : candidate.capitalized) : candidate
        }
        pendingPrefix = words.isEmpty ? nil : prefix
        suggestionWords = words
        let signature = state.language.rawValue + "|" + prefix + "|" + words.joined(separator: "|")
        guard suggestionSignature != signature else { return }
        suggestionSignature = signature
        if words.isEmpty {
            if !suggestions.arrangedSubviews.isEmpty { clear(suggestions) }
            return
        }
        if suggestions.arrangedSubviews.count != words.count || !(suggestions.arrangedSubviews.first is UIButton) {
            clear(suggestions)
            for index in words.indices {
                let button = makeButton(""); button.titleLabel?.font = .systemFont(ofSize: 16)
                button.addAction(UIAction { [weak self] _ in self?.acceptSuggestion(at: index) }, for: .touchUpInside)
                suggestions.addArrangedSubview(button)
            }
        }
        for (view, word) in zip(suggestions.arrangedSubviews, words) { (view as? UIButton)?.setTitle(word, for: .normal) }
    }
    private func acceptSuggestion(at index: Int) {
        guard suggestionWords.indices.contains(index), let prefix = pendingPrefix else { return }
        accept(suggestionWords[index], prefix: prefix)
    }
    private func accept(_ word: String, prefix: String) {
        // Recheck host context: a selection or cursor move invalidates the candidate.
        guard pendingPrefix == prefix, let context = textDocumentProxy.documentContextBeforeInput,
              LocalSuggestionProvider.trailingWord(in: context) == prefix,
              textDocumentProxy.selectedText == nil else { updateContext(); return }
        correctionUndo = nil; suppressedCorrection = nil
        for _ in prefix { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(word + " "); updateContext()
    }
    @objc private func alternatePress(_ gesture: UILongPressGestureRecognizer) {
        guard let button = gesture.view as? UIButton else { return }
        switch gesture.state {
        case .began:
            hideKeyPreview(); stopDeleting()
            let base = button.title(for: .normal)?.lowercased() ?? ""
            let alternatives = state.symbols ? state.language.alternatives(for: base) : state.language.holdAlternatives(for: base, symbolsEnabled: settings.extraSymbols)
            let rect = button.convert(button.bounds, to: view)
            let opensLeft = rect.midX > view.bounds.midX
            let choices = alternatives + [base]
            let values = opensLeft ? Array(choices.reversed()) : choices
            guard values.count > 1 else { return }
            popupValues = values; popupIndex = opensLeft ? values.count - 1 : 0
            popupInitialIndex = popupIndex
            let panel = UIView(); panel.backgroundColor = .secondarySystemBackground
            panel.layer.cornerRadius = 12; panel.layer.borderWidth = 1; panel.layer.borderColor = UIColor.separator.cgColor
            let width = min(CGFloat(values.count) * 40, view.bounds.width - 8)
            let origin = rect.midX - (CGFloat(popupIndex) + 0.5) * width / CGFloat(values.count)
            panel.frame = CGRect(x: min(max(4, origin), view.bounds.width - width - 4), y: max(2, rect.minY - 48), width: width, height: 44)
            for (index, value) in values.enumerated() {
                let label = UILabel(frame: CGRect(x: CGFloat(index) * width / CGFloat(values.count), y: 0, width: width / CGFloat(values.count), height: 44))
                label.textAlignment = .center; label.text = state.symbols || state.shift == .off ? value : value.uppercased(); label.font = .systemFont(ofSize: 23)
                panel.addSubview(label); popupLabels.append(label)
            }
            view.addSubview(panel); popup = panel
            popupStartX = gesture.location(in: panel).x
            performFeedback(); highlightPopup()
        case .changed:
            guard let panel = popup else { return }
            let point = gesture.location(in: panel)
            let offset = (point.x - popupStartX) / (panel.bounds.width / CGFloat(popupValues.count))
            let index = min(max(0, popupInitialIndex + Int(offset.rounded())), popupValues.count - 1)
            if index != popupIndex { popupIndex = index; performFeedback(); highlightPopup() }
        case .ended:
            let value = popupValues.indices.contains(popupIndex) ? popupValues[popupIndex] : nil
            dismissPopup(); if let value { insert(value) }
        case .cancelled, .failed: dismissPopup()
        default: break
        }
    }
    private func highlightPopup() {
        for (index, label) in popupLabels.enumerated() { label.backgroundColor = index == popupIndex ? .systemIndigo.withAlphaComponent(0.25) : .clear }
    }
    private func dismissPopup() { popup?.removeFromSuperview(); popup = nil; popupLabels.removeAll(); popupValues.removeAll() }
    deinit { previewHide?.cancel(); settingsHintTask?.cancel(); trailTimer?.invalidate() }
}
