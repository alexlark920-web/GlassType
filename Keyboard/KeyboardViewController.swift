import UIKit
import KeyboardCore

/// Character caps may lift. Function keys and the entire bottom row only change
/// brightness; their hit targets always stay in place.
private enum KeyPressBehavior: Equatable { case character, function, spacebar }

private final class SuggestionButton: UIButton {
    private let pressedFill = UIColor.label.withAlphaComponent(0.10)

    override var isHighlighted: Bool {
        didSet {
            guard oldValue != isHighlighted else { return }
            UIView.animate(withDuration: 0.075, delay: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
                self.backgroundColor = self.isHighlighted ? self.pressedFill : .clear
            }
        }
    }
}

private final class PredictionRequest {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

private class KeyButton: UIButton {
    private let face = UIView()
    private let pressShade = UIView()
    private let sheen = CAGradientLayer()
    private var glass: UIVisualEffectView?
    private var trackpadAppearance = false
    var routedHighlight = false { didSet { updatePressAppearance(animated: true) } }
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
        glass?.frame = face.bounds; glass?.layer.cornerRadius = keyRadius
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
        if #available(iOS 26.0, *), !reduced, !contrast {
            let effect = UIGlassEffect(style: .regular)
            effect.tintColor = resolved.withAlphaComponent(dark ? 0.34 : 0.16)
            // Keep feedback under our touch router; native gesture handling
            // must not compete with sliding letters, holds or the trackpad.
            effect.isInteractive = false
            if let glass { glass.effect = effect }
            else {
                let material = UIVisualEffectView(effect: effect)
                material.isUserInteractionEnabled = false; material.isAccessibilityElement = false
                material.layer.cornerCurve = .continuous; material.clipsToBounds = true
                face.insertSubview(material, at: 0); glass = material
            }
        } else { glass?.removeFromSuperview(); glass = nil }
        face.backgroundColor = glass != nil ? .clear : (reduced ? resolved.withAlphaComponent(1) : resolved)
        face.layer.borderWidth = contrast ? 1 : (glass == nil ? 0.5 : 0)
        face.layer.borderColor = UIColor.white.withAlphaComponent(contrast ? (dark ? 0.42 : 0.95) : (dark ? 0.14 : 0.65)).cgColor
        CATransaction.begin(); CATransaction.setDisableActions(true)
        sheen.colors = [UIColor.white.withAlphaComponent(dark ? 0.12 : 0.35).cgColor,
                        UIColor.white.withAlphaComponent(dark ? 0.025 : 0.055).cgColor,
                        UIColor.clear.cgColor]
        sheen.opacity = reduced ? 0 : (glass == nil ? 1 : 0.28)
        CATransaction.commit()
        setNeedsLayout()
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
        let down = (isHighlighted || routedHighlight) && !trackpadAppearance
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
            let transform = down && lifts && !reducedMotion ? CGAffineTransform(translationX: 0, y: -2.2).scaledBy(x: 1.025, y: 1.035) : .identity
            self.face.transform = transform
            self.face.layer.shadowOpacity = self.trackpadAppearance ? 0 : (down && lifts ? (dark ? 0.22 : 0.14) : (dark ? 0.10 : 0.07))
            for child in self.subviews where child !== self.face {
                child.transform = transform
                child.alpha = self.trackpadAppearance ? 0 : 1
            }
        }
        pressShade.layer.removeAllAnimations(); pressShade.alpha = down ? pressedAlpha : 0
        if !animated || reducedMotion { changes() }
        else if !lifts {
            UIView.animate(withDuration: 0.06, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut], animations: changes)
        } else {
            UIView.animate(withDuration: down ? 0.065 : 0.14, delay: 0,
                           usingSpringWithDamping: down ? 0.88 : 0.82,
                           initialSpringVelocity: down ? 0.7 : 0.9,
                           options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
        }
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}

/// UIKit keeps one original receiver per finger; this text control explicitly
/// follows a candidate until lift. Function controls retain their own tracking.
private final class TextKeyButton: KeyButton {
    var textValue = ""
    var commit: ((String) -> Void)?
    private var contact = TextTouchSession()
    private var revision: UInt = 0
    private var presented: Int?
    private var touchIdentifier: ObjectIdentifier?
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        cancelContact()
        guard let surface = touchSurface, let model = surface.recognizer,
              super.beginTracking(touch, with: event) else { return false }
        touchIdentifier = ObjectIdentifier(touch); surface.beginTextContact(touch)
        revision = surface.revision
        contact.begin(at: touch.location(in: surface), keyIndex: geometryIndex, model: model)
        select(contact.selectedKey)
        isHighlighted = false
        return contact.phase == .tracking
    }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard let surface = touchSurface, revision == surface.revision, let model = surface.recognizer,
              contact.phase == .tracking else { cancelContact(); return false }
        select(contact.move(to: touch.location(in: surface), model: model))
        isHighlighted = false
        return true
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        guard let touch, let surface = touchSurface, revision == surface.revision,
              surface.canCommitText?() != false, window != nil, let model = surface.recognizer, contact.phase == .tracking else {
            cancelContact(); super.cancelTracking(with: event); return
        }
        let index = contact.end(at: touch.location(in: surface), model: model)
        select(index)
        let value = index.flatMap { model.geometry.keys[$0].role.character }
        surface.finishSelection(presented, cancelled: value == nil, revision: revision)
        if let touchIdentifier { surface.finishTextContact(touchIdentifier) }
        touchIdentifier = nil
        presented = nil; isHighlighted = false
        super.endTracking(touch, with: event)
        if let value { commit?(value) }
    }
    override func cancelTracking(with event: UIEvent?) {
        cancelContact(); super.cancelTracking(with: event)
    }
    override func didMoveToWindow() {
        super.didMoveToWindow(); if window == nil { cancelContact() }
    }
    override func accessibilityActivate() -> Bool {
        guard isEnabled, !textValue.isEmpty else { return false }
        commit?(textValue); return true
    }
    private func select(_ index: Int?) {
        touchSurface?.changeSelection(from: presented, to: index, revision: revision)
        presented = index
    }
    private func cancelContact() {
        if let touchIdentifier { touchSurface?.finishTextContact(touchIdentifier) }
        touchIdentifier = nil
        touchSurface?.finishSelection(presented, cancelled: true, revision: revision)
        presented = nil; contact.cancel(); isHighlighted = false
    }
}

/// UIButton tracking owns the whole touch, so swipe/hold never also insert a
/// space. Accessibility activation remains a normal space action.
private final class SpacebarButton: KeyButton {
    var onAction: ((SpacebarInteraction.Action) -> Void)?
    var onCursorEnd: (() -> Void)?
    private var interaction = SpacebarInteraction()
    private var holdTimer: Timer?
    private var cursorRepeatTimer: Timer?
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        cancelInteraction()
        _ = super.beginTracking(touch, with: event)
        let point = touch.location(in: self)
        interaction.begin(x: Double(point.x), y: Double(point.y), at: ProcessInfo.processInfo.systemUptime)
        isHighlighted = true
        let timer = Timer(timeInterval: SpacebarInteraction.holdDuration, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.send(self.interaction.hold(at: ProcessInfo.processInfo.systemUptime))
            self.holdTimer = nil
        }
        holdTimer = timer; RunLoop.main.add(timer, forMode: .common)
        return true
    }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let point = touch.location(in: self)
        send(interaction.update(x: Double(point.x), y: Double(point.y), at: ProcessInfo.processInfo.systemUptime))
        return true
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        holdTimer?.invalidate(); holdTimer = nil
        cursorRepeatTimer?.invalidate(); cursorRepeatTimer = nil
        let action: SpacebarInteraction.Action
        if let touch {
            let point = touch.location(in: self)
            action = interaction.end(x: Double(point.x), y: Double(point.y), at: ProcessInfo.processInfo.systemUptime)
        } else { interaction.cancel(); action = .none }
        super.endTracking(touch, with: event)
        isHighlighted = false
        send(action)
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
        holdTimer?.invalidate(); holdTimer = nil; cursorRepeatTimer?.invalidate(); cursorRepeatTimer = nil
        interaction.cancel(); isHighlighted = false
        if wasCursor { onCursorEnd?() }
    }
    private func send(_ action: SpacebarInteraction.Action) {
        if case .cursorBegan = action, cursorRepeatTimer == nil {
            let timer = Timer(timeInterval: 0.075, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.send(self.interaction.repeatCursorAtEdge(buttonWidth: Double(self.bounds.width)))
            }
            cursorRepeatTimer = timer; RunLoop.main.add(timer, forMode: .common)
        }
        onAction?(action)
    }
    override func accessibilityActivate() -> Bool { onAction?(.insertSpace); return true }
    deinit { holdTimer?.invalidate(); cursorRepeatTimer?.invalidate() }
}

private final class DeleteKeyButton: KeyButton {
    var deleteAction: (() -> Void)?
    var pressBeganAction: (() -> Void)?
    var pressEndedWithoutSwipeAction: (() -> Void)?
    var repeatDeleteAction: (() -> Void)?
    var repeatDeleteWordAction: (() -> Void)?
    var deleteWordAction: (() -> Void)?
    var canSwipeWord: (() -> Bool)?
    private var delay: Timer?
    private var start: CGPoint = .zero
    private var swiped = false, repeated = false, deleteGestureActive = false, swipeEligible = false
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        cancelInteraction(); _ = super.beginTracking(touch, with: event)
        deleteGestureActive = true; start = touch.location(in: self); isHighlighted = true
        swipeEligible = canSwipeWord?() == true
        heldSince = ProcessInfo.processInfo.systemUptime
        pressBeganAction?()
        scheduleRepeat(after: BackspaceEngine.initialDelay)
        return true
    }
    private var heldSince: TimeInterval = 0
    private let engine = BackspaceEngine()
    private func scheduleRepeat(after interval: TimeInterval) {
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            guard let self, self.deleteGestureActive, !self.swiped else { return }
            self.repeated = true
            let elapsed = ProcessInfo.processInfo.systemUptime - self.heldSince
            switch self.engine.nextDeletion(heldFor: elapsed) {
            case .character:
                if let action = self.repeatDeleteAction { action() } else { self.deleteAction?() }
            case .word: self.repeatDeleteWordAction?()
            }
            guard self.deleteGestureActive, !self.swiped else { return }
            self.scheduleRepeat(after: self.engine.nextInterval(heldFor: ProcessInfo.processInfo.systemUptime - self.heldSince))
        }
        delay = timer; RunLoop.main.add(timer, forMode: .common)
    }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard deleteGestureActive else { return false }
        let p = touch.location(in: self)
        if engine.shouldSwipeDelete(start: start, current: p, repeated: repeated, enabled: swipeEligible) {
            swiped = true; delay?.invalidate(); delay = nil
        }
        if !point(inside: p, with: event), !swiped {
            delay?.invalidate(); delay = nil
            if repeated { isHighlighted = false }
        } else if !swiped && delay == nil {
            isHighlighted = true
            let elapsed = ProcessInfo.processInfo.systemUptime - heldSince
            scheduleRepeat(after: max(0.035, BackspaceEngine.initialDelay - elapsed))
        }
        return true
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        guard deleteGestureActive else { super.endTracking(touch, with: event); return }
        let p = touch?.location(in: self) ?? start
        let eligible = !repeated && swipeEligible
        let word = swiped || engine.shouldSwipeDelete(start: start, current: p, repeated: repeated, enabled: eligible)
        cancelInteraction(); super.endTracking(touch, with: event)
        if word { deleteWordAction?() } else { pressEndedWithoutSwipeAction?() }
    }
    override func cancelTracking(with event: UIEvent?) { cancelInteraction(); pressEndedWithoutSwipeAction?(); super.cancelTracking(with: event) }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { cancelInteraction() } }
    func cancelInteraction() { deleteGestureActive = false; delay?.invalidate(); delay = nil; swiped = false; repeated = false; swipeEligible = false; isHighlighted = false }
    override func accessibilityActivate() -> Bool { deleteAction?(); return true }
    deinit { delay?.invalidate() }
}

final class KeyboardViewController: UIInputViewController, UIGestureRecognizerDelegate {
    private var state = InputState()
    private let theme = KeyboardTheme.material
    private var settings = KeyboardSettings()
    private let predictionEngine = PredictionEngine()
    private let predictionProfile = LocalPredictionModelStore()
    private let predictionQueue = DispatchQueue(label: "GlassType.prediction", qos: .userInitiated)
    private let glideDecoder = GlideDecoderActor()
    private var glideDecodeTask: Task<Void, Never>?
    private var sharedSettingsObserver: DarwinNotificationObserver?
    private var learnedWordsObserver: DarwinNotificationObserver?
    private var learnedPersonalWords: [String] = []
    private var learnedWordsGeneration: UInt = 0
    private var personalLexiconRepository: PersonalLexiconRepository?
    private var predictionGeneration: UInt = 0
    private var pendingPredictionRequest: PredictionRequest?
    private let rows = UIStackView()
    private let keyPlane = KeyboardTouchSurface(frame: .zero)
    private var touchAdaptation = TouchCalibrationStorage.load()
    private var pendingCalibrationSamples = 0
    private let lexiconQueue = DispatchQueue(label: "GlassType.lexicon", qos: .userInitiated)
    private struct GlideRequest: Sendable {
        let points: [CGPoint]
        let centers: [String: CGPoint]
        let language: KeyboardLanguage
    }
    private enum DeferredInput {
        case text(String), backspace(Bool), deleteWord, shift, symbols, emoji, language(LanguageDirection), glide(GlideRequest), suggestion(String, String)
    }
    private var pendingInput = PendingInputSequence<DeferredInput>()
    private var drainingInput = false
    private var trailSamples: [(point: CGPoint, time: TimeInterval)] = []
    private var trailTimer: Timer?
    private let suggestions = UIStackView()
    private let toolbar = UIStackView()
    private lazy var emojiCatalog = EmojiCatalog.bundled()
    private lazy var emojiItems = emojiCatalog.sections.flatMap(\.entries)
    private var emojiKeyboardView: EmojiKeyboardView?
    private var emojiSearchActive = false
    private var emojiSearchQuery = ""
    private weak var emojiSearchLabel: UILabel?
    private var feedback: UIImpactFeedbackGenerator?
    private var settingsPanel: UIView?
    private var languageSwitches: [KeyboardLanguage: UISwitch] = [:]
    private var popupStartX: CGFloat = 0
    private var popupInitialIndex = 0
    private let keyPreview = KeyPreviewPresenter()
    private var backspaceEngine = BackspaceEngine()
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
    private var renderedLetterCase: Bool?
    private weak var spaceButton: SpacebarButton?
    private var cursorMode = false
    private var cursorDocument: String?
    private var lastWidth: CGFloat = 0
    private var lastHeight: CGFloat = 0
    private var lastLandscape = false
    private var pendingPrefix: String?
    private var deleteSwipeRestoreSuffix = ""
    private var suggestionWords: [String] = []
    private var suggestionSignature: String?
    private let textService = KeyboardTextService()
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
    private var completedWord: CompletedWordInsertion?
    private var glideSnapshot: (InputContextSnapshot, KeyboardLanguage)?
    private let glideTrail = CAShapeLayer()
    private lazy var glidePan: GlideTouchRecognizer = {
        let pan = GlideTouchRecognizer(target: self, action: #selector(glideChanged(_:)))
        pan.delegate = self; pan.coordinateView = view
        pan.mayBegin = { [weak self] first, last in
            guard let self else { return false }
            let a = self.keyPlane.keyIndex(at: self.view.convert(first, to: self.keyPlane))
            let b = self.keyPlane.keyIndex(at: self.view.convert(last, to: self.keyPlane))
            guard let b, let key = self.keyPlane.recognizer?.geometry.keys[b], key.role.character?.allSatisfy(\.isLetter) == true else { return false }
            let pitch = self.keyPlane.recognizer?.geometry.pitch ?? .zero
            return GlideActivation.shouldBegin(start: first, current: last, startKey: a, currentKey: b,
                                              minimumDistance: GlideActivation.minimumTravel(keyPitch: pitch))
        }
        return pan
    }()

    override func loadView() {
        // Use the system keyboard surface, rather than layering a rectangular
        // extra blur over only the extension and creating a seam at the dock.
        let keyboard = UIInputView(frame: .zero, inputViewStyle: .keyboard)
        keyboard.allowsSelfSizing = true
        keyboard.isMultipleTouchEnabled = true
        keyboard.isExclusiveTouch = false
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
        rows.isMultipleTouchEnabled = true
        toolbar.heightAnchor.constraint(equalToConstant: 32).isActive = true
        view.addSubview(rows)
        rows.addGestureRecognizer(glidePan)
        keyPlane.didLayoutKey = { button, key in
            (button as? KeyButton)?.visualCapFrame = key.visualFrame.offsetBy(dx: -key.slotFrame.minX, dy: -key.slotFrame.minY)
        }
        keyPlane.canLearn = { [weak self] in self?.canLearnTouch == true }
        keyPlane.didLearn = { [weak self] x, y in self?.learnTouch(x: x, y: y) }
        keyPlane.canCommitText = { [weak self] in self?.cursorMode == false && self?.settingsPanel == nil }
        keyPlane.didChangePress = { button, down in (button as? KeyButton)?.routedHighlight = down }
        keyPlane.didSelectTextKey = { [weak self] button in
            guard let key = button as? KeyButton else { return }
            self?.showKeyPreview(for: key)
        }
        keyPlane.didFinishTextKey = { [weak self] button, cancelled in
            guard let key = button as? KeyButton else { return }
            self?.finishKeyPreview(for: key, immediately: cancelled)
        }
        glideTrail.fillColor = nil; glideTrail.lineWidth = 4.5; glideTrail.lineCap = .round; glideTrail.lineJoin = .round
        view.layer.addSublayer(glideTrail)
        keyPreview.attach(to: view.layer)
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            rows.topAnchor.constraint(equalTo: view.topAnchor, constant: 5),
            rows.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        let height = view.heightAnchor.constraint(equalToConstant: 280)
        height.priority = .init(999); height.isActive = true; heightConstraint = height
        sharedSettingsObserver = DarwinNotificationCenter.observe(name: DarwinNotificationCenter.settingsUpdatedName) { [weak self] in
            Task { @MainActor [weak self] in self?.reloadSettings() }
        }
        learnedWordsObserver = DarwinNotificationCenter.observe(name: PersonalLexiconRepository.learnedWordsNotificationName) { [weak self] in
            Task { @MainActor [weak self] in self?.refreshLearnedWords() }
        }
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
        applyKeyboardHeight()
        // A landscape keyboard can occupy a narrow split-screen host; use screen orientation too.
        let landscape = (view.window?.windowScene?.interfaceOrientation.isLandscape ?? false)
        if abs(lastWidth - view.bounds.width) > 1 || abs(lastHeight - view.bounds.height) > 1 || landscape != lastLandscape {
            lastWidth = view.bounds.width; lastHeight = view.bounds.height; lastLandscape = landscape
            applyTouchConfiguration()
            cancelGlide(); hideKeyPreview(); spaceButton?.cancelInteraction(); stopDeleting(); dismissPopup()
            for button in keyPlane.keyViews where button.isTracking { button.cancelTracking(with: nil) }
            for (button, _) in letterButtons { button.titleLabel?.font = .systemFont(ofSize: keyFontSize()) }
            symbolsButton?.titleLabel?.font = .systemFont(ofSize: keyFontSize() * 0.765)
        }
    }
    private func applyKeyboardHeight() {
        guard view.bounds.width > 0 else { return }
        let landscape = view.window?.windowScene?.interfaceOrientation.isLandscape ?? false
        let base: CGFloat = landscape ? (settings.compactKeys ? 188 : 202) : (settings.compactKeys ? 254 : 278)
        let desired = KeyboardSizing.height(base: base * 1.05, scale: settings.keyboardHeightScale,
                                            hasToolbar: needsToolbar, bottomInset: view.safeAreaInsets.bottom)
        if heightConstraint?.constant != desired { heightConstraint?.constant = desired }
    }
    override func textDidChange(_ textInput: UITextInput?) {
        invalidatePendingInput(); cancelCursorIfDocumentChanged(); invalidateSpaceSnapshot(); invalidateCorrectionUndo()
        updateContext()
    }
    override func selectionDidChange(_ textInput: UITextInput?) { invalidatePendingInput(); cancelCursorIfDocumentChanged(); invalidateSpaceSnapshot(); dismissPopup(); invalidateCorrectionUndo(); updateContext() }
    private func reloadSettings() {
        settings = KeyboardSettings.loadKeyboard(fullAccess: hasFullAccess)
        personalLexiconRepository = hasFullAccess ? (personalLexiconRepository ?? (try? PersonalLexiconRepository())) : nil
        refreshLearnedWords()
        let profileStore = predictionProfile
        predictionQueue.async { _ = profileStore.snapshot() }
        configureFeedback()
        state.language = KeyboardSettings.lastUsedLanguage(enabled: settings.languages)
        state.emoji = false
        KeyboardSettings.rememberLanguage(state.language)
        switch settings.theme {
        case .system: overrideUserInterfaceStyle = .unspecified
        case .light: overrideUserInterfaceStyle = .light
        case .dark: overrideUserInterfaceStyle = .dark
        }
        prewarmLexicon()
        rebuild()
    }
    private func refreshLearnedWords() {
        learnedWordsGeneration &+= 1
        let generation = learnedWordsGeneration
        let repository = personalLexiconRepository
        predictionQueue.async { [weak self] in
            let words = (try? repository?.topWords(limit: 500)) ?? []
            DispatchQueue.main.async { [weak self] in
                guard let self, self.learnedWordsGeneration == generation else { return }
                self.learnedPersonalWords = words
                self.refreshSuggestions()
            }
        }
    }
    private var effectivePersonalLexicon: PersonalLexicon {
        var lexicon = settings.personalLexicon
        var seen = Set<String>()
        lexicon.knownWords = (learnedPersonalWords + lexicon.knownWords).filter {
            seen.insert($0.precomposedStringWithCanonicalMapping.lowercased()).inserted
        }
        return lexicon.sanitized()
    }
    private func clear(_ stack: UIStackView) {
        stack.isUserInteractionEnabled = true
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
    }
    private func rebuild(preservingInput: Bool = false) {
        predictionGeneration &+= 1
        pendingPredictionRequest?.cancel(); pendingPredictionRequest = nil
        if preservingInput { resetGlidePresentation() } else { cancelGlide() }
        lastSpace = nil; glideWords = []; glideUndo = nil; deletionUndo = nil
        hideKeyPreview(); spaceButton?.cancelInteraction(); spaceButton = nil; symbolsButton = nil
        stopDeleting(); dismissPopup(); hideLocalSettings(); clear(rows); clear(toolbar); clear(suggestions); letterButtons.removeAll(); shiftButton = nil; renderedShift = nil; renderedLetterCase = nil; emojiSearchLabel = nil
        suggestionSignature = nil; suggestionWords.removeAll(); correctionUndo = nil
        view.setNeedsLayout()
        suggestions.axis = .horizontal; suggestions.distribution = .fillEqually; suggestions.spacing = 6
        toolbar.axis = .horizontal; toolbar.spacing = 6
        if emojiSearchActive { configureEmojiSearchToolbar() }
        else { toolbar.addArrangedSubview(suggestions) }
        if needsToolbar { rows.addArrangedSubview(toolbar) }
        if lexiconEditing != nil { configureEditorBar() }
        for button in keyPlane.keyViews { button.removeFromSuperview() }
        keyPlane.keyViews.removeAll(keepingCapacity: true)
        emojiKeyboardView = nil
        if state.emoji {
            let emojiView = EmojiKeyboardView(catalog: emojiCatalog, theme: theme,
                                              interfaceLanguage: settings.interfaceLanguage,
                                              needsInputModeSwitch: needsInputModeSwitchKey)
            emojiView.onSelectEmoji = { [weak self] emoji in self?.insert(emoji) }
            emojiView.onSearch = { [weak self] in self?.beginEmojiSearch() }
            emojiView.onReturnToLetters = { [weak self] in self?.leaveEmojiKeyboard() }
            emojiView.onDeletePressBegan = { [weak self] in self?.performFeedback(); self?.deleteOnce() }
            emojiView.onDelete = { [weak self] in self?.deleteOnce(allowGlideWord: false) }
            emojiView.inputModeSwitchButton?.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
            emojiKeyboardView = emojiView
            rows.addArrangedSubview(emojiView)
            refreshSuggestions()
            return
        }
        keyPlane.language = state.language; keyPlane.symbolPage = state.symbols ? state.symbolPage : nil
        keyPlane.customRows = nil
        keyPlane.thirdRowUsesModeSwitch = false
        keyPlane.compact = settings.compactKeys; keyPlane.needsSystemKey = needsInputModeSwitchKey
        keyPlane.visualWidthScale = CGFloat(settings.visualKeyWidthScale)
        keyPlane.showsDebugZones = settings.debugTouchZones
        func attach(_ button: UIButton) {
            if let key = button as? KeyButton {
                key.touchSurface = keyPlane; key.geometryIndex = keyPlane.keyViews.count
                key.learningMaximumDuration = settings.holdDelay
            }
            keyPlane.keyViews.append(button); keyPlane.addKey(button)
        }
        let keyRows = state.symbols ? state.symbolPage.rows : state.language.rows
        for (index, keys) in keyRows.enumerated() {
            if index == 2 {
                let title = state.emoji ? "ABC" : (state.symbols ? state.symbolPage.switchTitle : "⇧")
                let leading = makeButton(title, special: true)
                leading.accessibilityLabel = state.emoji ? localized("Сменить на буквы") : (state.symbols ? localized("Другая страница символов") : localized("Shift — двойное нажатие: Caps Lock"))
                if state.emoji { leading.addAction(UIAction { [weak self] _ in self?.leaveEmojiKeyboard() }, for: .touchUpInside) }
                else { leading.addTarget(self, action: #selector(shiftTapped), for: .touchUpInside) }
                shiftButton = leading; attach(leading)
            }
            for key in keys {
                let button = makeButton(key)
                button.accessibilityLabel = key
                configureTextAction(button, text: key)
                let alternatives = state.emoji ? [] : (state.symbols ? state.symbolPage.holdAlternatives(for: key) : state.language.holdAlternatives(for: key, symbolsEnabled: settings.extraSymbols))
                configureHold(on: button, alternatives: alternatives)
                letterButtons.append((button, key)); attach(button)
            }
            if index == 2 {
                let delete = makeButton("⌫", special: true); delete.accessibilityLabel = localized("Удалить")
                deleteButton = delete as? DeleteKeyButton
                deleteButton?.deleteAction = { [weak self] in self?.deleteOnce() }
                deleteButton?.pressBeganAction = { [weak self] in self?.beginBackspacePress() }
                deleteButton?.pressEndedWithoutSwipeAction = { [weak self] in self?.deleteSwipeRestoreSuffix = "" }
                deleteButton?.repeatDeleteAction = { [weak self] in self?.deleteOnce(allowGlideWord: false) }
                deleteButton?.repeatDeleteWordAction = { [weak self] in self?.deleteWord(force: true) }
                deleteButton?.deleteWordAction = { [weak self] in self?.deleteWord() }
                deleteButton?.canSwipeWord = { [weak self] in
                    guard let self else { return false }
                    return self.settings.swipeDeleteWord && self.lexiconEditing == nil && !self.cursorMode &&
                        self.completedWord == nil && self.correctionUndo == nil && !self.emojiSearchActive
                }
                delete.accessibilityCustomActions = [UIAccessibilityCustomAction(name: localized("Удалить слово")) { [weak self] _ in self?.deleteWord(); return true }]
                attach(delete)
            }
        }
        let bottomStart = keyPlane.keyViews.count
        let symbols = makeButton(state.symbols ? "ABC" : "123", special: true)
        symbolsButton = symbols
        symbols.titleLabel?.font = .systemFont(ofSize: keyFontSize() * 0.765)
        symbols.addAction(UIAction { [weak self] _ in self?.toggleSymbols() }, for: .touchUpInside)
        attach(symbols)
        let language = makeButton("", special: true)
        languageButton = language as? KeyButton
        let languageSymbol = settings.emojiKeyEnabled ? "face.smiling" : "globe"
        language.setImage(UIImage(systemName: languageSymbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: settings.emojiKeyEnabled ? 19 : 21, weight: .regular)), for: .normal)
        language.tintColor = theme.foreground
        language.accessibilityLabel = localized(settings.emojiKeyEnabled ? "Эмодзи" : "Сменить язык")
        language.accessibilityValue = settings.emojiKeyEnabled ? nil : state.language.title
        language.accessibilityHint = localized("Удерживайте для настроек клавиатуры")
        language.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if self.settings.emojiKeyEnabled { self.toggleEmojiKeyboard() } else { self.cycleLanguage(.next) }
        }, for: .touchUpInside)
        let settingsPress = UILongPressGestureRecognizer(target: self, action: #selector(settingsHeld(_:)))
        settingsPress.minimumPressDuration = settings.holdDelay
        settingsPress.delaysTouchesBegan = false; settingsPress.delaysTouchesEnded = false
        language.addGestureRecognizer(settingsPress)
        language.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: localized("Настройки клавиатуры")) { [weak self] _ in self?.showLocalSettings(); return true },
            UIAccessibilityCustomAction(name: localized("Предыдущий язык")) { [weak self] _ in self?.cycleLanguage(.previous); return true }
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
            systemKeyboard.accessibilityLabel = localized("Другие системные клавиатуры")
            systemKeyboard.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
            attach(systemKeyboard)
        }
        let comma = makeButton(","); comma.accessibilityLabel = localized("Запятая")
        configureTextAction(comma, text: ",")
        attach(comma)
        let space = SpacebarButton(frame: .zero)
        configureButton(space, title: spaceTitle())
        spaceButton = space
        space.accessibilityLabel = localized("Пробел"); space.accessibilityValue = state.language.title
        space.accessibilityHint = localized("Быстрый свайп влево или вправо меняет язык. Удерживайте и двигайте палец для перемещения курсора.")
        space.titleLabel?.font = .systemFont(ofSize: 14)
        space.onAction = { [weak self] action in self?.handleSpaceAction(action) }
        space.onCursorEnd = { [weak self] in self?.setCursorMode(false) }
        space.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: localized("Следующий язык")) { [weak self] _ in self?.cycleLanguage(.next); return true },
            UIAccessibilityCustomAction(name: localized("Предыдущий язык")) { [weak self] _ in self?.cycleLanguage(.previous); return true },
            UIAccessibilityCustomAction(name: localized("Курсор влево")) { [weak self] _ in self?.moveCursor(-1); return true },
            UIAccessibilityCustomAction(name: localized("Курсор вправо")) { [weak self] _ in self?.moveCursor(1); return true }
        ]
        attach(space)
        let punctuation = makeButton("."); configureTextAction(punctuation, text: ".")
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

    private func configureEmojiSearchToolbar() {
        toolbar.distribution = .fill
        let capsule = UIView()
        capsule.translatesAutoresizingMaskIntoConstraints = false
        capsule.backgroundColor = theme.key.withAlphaComponent(0.54)
        capsule.layer.cornerRadius = 12
        capsule.layer.cornerCurve = .continuous
        capsule.layer.borderWidth = 0.5
        capsule.layer.borderColor = UIColor.white.withAlphaComponent(0.14).cgColor

        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = theme.foreground.withAlphaComponent(0.7)
        icon.isAccessibilityElement = false
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13)
        label.textColor = theme.foreground
        label.lineBreakMode = .byTruncatingTail
        label.text = emojiSearchQuery.isEmpty ? localized("Поиск эмодзи") : emojiSearchQuery
        emojiSearchLabel = label
        let close = UIButton(type: .system)
        close.translatesAutoresizingMaskIntoConstraints = false
        close.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)), for: .normal)
        close.tintColor = theme.foreground.withAlphaComponent(0.72)
        close.accessibilityLabel = localized("Закрыть поиск эмодзи")
        close.addAction(UIAction { [weak self] _ in self?.endEmojiSearch(returnToEmoji: true) }, for: .touchUpInside)
        capsule.addSubview(icon); capsule.addSubview(label); capsule.addSubview(close)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: 9),
            icon.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
            label.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -3),
            close.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -6),
            close.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 22),
            capsule.heightAnchor.constraint(equalToConstant: 34)
        ])
        label.accessibilityLabel = localized("Поиск эмодзи")
        label.accessibilityValue = emojiSearchQuery
        capsule.heightAnchor.constraint(equalToConstant: 34).isActive = true
        capsule.widthAnchor.constraint(equalToConstant: min(max(view.bounds.width * 0.38, 118), 158)).isActive = true
        toolbar.addArrangedSubview(capsule)
        suggestions.setContentHuggingPriority(.defaultLow, for: .horizontal)
        suggestions.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        toolbar.addArrangedSubview(suggestions)
        refreshEmojiSearchResults()
    }

    private func beginEmojiSearch() {
        guard !emojiSearchActive else { return }
        emojiSearchActive = true
        emojiSearchQuery = ""
        state.emoji = false
        state.symbols = false
        rebuild()
    }

    private func endEmojiSearch(returnToEmoji: Bool) {
        guard emojiSearchActive else { return }
        emojiSearchActive = false
        emojiSearchQuery = ""
        state.emoji = returnToEmoji
        if returnToEmoji { state.symbols = false }
        rebuild()
    }

    private func refreshEmojiSearchResults() {
        guard emojiSearchActive else { return }
        emojiSearchLabel?.text = emojiSearchQuery.isEmpty ? localized("Поиск эмодзи") : emojiSearchQuery
        suggestionSignature = "emoji-search:" + emojiSearchQuery
        clear(suggestions)
        guard !emojiSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let hint = UILabel()
            hint.text = localized("Введите запрос")
            hint.font = .systemFont(ofSize: 12)
            hint.textColor = theme.foreground.withAlphaComponent(0.62)
            hint.textAlignment = .center
            suggestions.addArrangedSubview(hint)
            return
        }
        let items = EmojiSearch.search(emojiSearchQuery, in: emojiItems, limit: 7)
        for item in items {
            let button = makeSuggestionButton(item.emoji)
            button.titleLabel?.font = .systemFont(ofSize: 23)
            button.accessibilityLabel = item.name
            button.addAction(UIAction { [weak self] _ in self?.selectEmojiSearchResult(item.emoji) }, for: .touchUpInside)
            suggestions.addArrangedSubview(button)
        }
        if items.isEmpty {
            let hint = UILabel()
            hint.text = localized("Нет совпадений")
            hint.font = .systemFont(ofSize: 12)
            hint.textColor = theme.foreground.withAlphaComponent(0.62)
            hint.textAlignment = .center
            suggestions.addArrangedSubview(hint)
        }
    }

    private func selectEmojiSearchResult(_ emoji: String) {
        guard emojiSearchActive else { return }
        emojiSearchActive = false
        emojiSearchQuery = ""
        state.emoji = true
        state.symbols = false
        insert(emoji)
        rebuild()
    }
    private func makeButton(_ title: String, special: Bool = false) -> UIButton {
        let button: KeyButton
        if title == "⌫" { button = DeleteKeyButton(frame: .zero) }
        else if !special && title.count == 1 { button = TextKeyButton(frame: .zero) }
        else { button = KeyButton(frame: .zero) }
        configureButton(button, title: title)
        button.showsCharacterPreview = !special && title.count == 1
        button.pressBehavior = !special && title.count == 1 ? .character : .function
        return button
    }
    private func makeSuggestionButton(_ title: String = "") -> UIButton {
        let button = SuggestionButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.setTitleColor(theme.foreground, for: .normal)
        button.tintColor = theme.foreground
        button.titleLabel?.font = .systemFont(ofSize: 15)
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.backgroundColor = .clear
        button.layer.cornerRadius = 10
        button.layer.cornerCurve = .continuous
        button.clipsToBounds = true
        button.layer.borderWidth = 0
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 3, bottom: 0, right: 3)
        return button
    }
    private func configureTextAction(_ button: UIButton, text: String) {
        (button as? TextKeyButton)?.textValue = text
        (button as? TextKeyButton)?.commit = { [weak self] value in self?.insert(value) }
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
            self?.synchronizeCapitalization(); self?.refreshLabels()
            self?.performFeedback()
            if let button {
                if button === self?.languageButton { self?.scheduleSettingsHint(for: button) }
                else { self?.showKeyPreview(for: button) }
            }
        }, for: .touchDown)
        button.addAction(UIAction { [weak self, weak button] _ in
            if let button, !(button is TextKeyButton) { self?.finishKeyPreview(for: button, immediately: false) }
        }, for: .touchUpInside)
        button.addAction(UIAction { [weak self, weak button] _ in
            if let button, !(button is TextKeyButton) { self?.finishKeyPreview(for: button, immediately: true) }
        }, for: [.touchUpOutside, .touchCancel, .touchDragExit])
        button.addAction(UIAction { [weak self, weak button] _ in
            if let button, !(button is TextKeyButton) { self?.showKeyPreview(for: button) }
        }, for: .touchDragEnter)
    }
    private func localized(_ source: String) -> String {
        GlassTypeText.translate(source, to: settings.interfaceLanguage)
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
        previewKey = button
        keyPreview.show(layout: placement, text: text, fill: theme.key, ink: theme.foreground)
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
        keyPreview.hide()
    }
    private var canLearnTouch: Bool {
        settings.touchAdaptationEnabled && !state.symbols && !state.emoji && !cursorMode && settingsPanel == nil && lexiconEditing == nil &&
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
        lexiconQueue.async { [weak self] in
            GlideDecoder.prepare(language: language)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.state.language == language, self.view.window != nil else { return }
                self.refreshSuggestions()
            }
        }
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
        press.allowableMovement = 8
        press.delaysTouchesBegan = false; press.delaysTouchesEnded = false
        button.addGestureRecognizer(press)
        button.accessibilityHint = localized("Удерживайте для: ") + alternatives.joined(separator: ", ")
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
        settingsPanel?.removeFromSuperview(); settingsPanel = nil; languageSwitches.removeAll(); rows.isHidden = false
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
        let title = UILabel(); title.text = localized("Клавиатура")
        title.font = .preferredFont(forTextStyle: .headline); title.adjustsFontForContentSizeCategory = true
        title.adjustsFontSizeToFitWidth = true; title.minimumScaleFactor = 0.8
        title.accessibilityTraits.insert(.header)
        title.translatesAutoresizingMaskIntoConstraints = false; header.addSubview(title)
        let done = UIButton(type: .system); done.setTitle(localized("Готово"), for: .normal)
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
            let caption = UILabel(); caption.text = localized(heading)
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
        @discardableResult
        func toggle(_ text: String, value: Bool, group: UIStackView, change: @escaping (Bool) -> Void) -> UISwitch {
            let title = localized(text)
            let line = UIControl(); line.isAccessibilityElement = false
            line.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            let label = UILabel(); label.text = title; label.numberOfLines = 0
            label.font = .preferredFont(forTextStyle: .body); label.adjustsFontForContentSizeCategory = true
            label.isAccessibilityElement = false; label.translatesAutoresizingMaskIntoConstraints = false
            line.addSubview(label)
            // Default UISwitch styling lets the running iOS choose its own
            // thumb, track, accessibility appearance and interaction.
            let control = UISwitch(); control.isOn = value; control.accessibilityLabel = title
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
                guard let control, control.isEnabled else { return }
                control.setOn(!control.isOn, animated: true); control.sendActions(for: .valueChanged)
            }, for: .touchUpInside)
            append(line, to: group)
            return control
        }
        func segmented(_ text: String, control: UISegmentedControl, group: UIStackView) {
            let title = localized(text)
            let container = UIView()
            let label = UILabel(); label.text = title; label.numberOfLines = 0
            label.font = .preferredFont(forTextStyle: .body); label.adjustsFontForContentSizeCategory = true
            label.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(label)
            control.accessibilityLabel = title; control.translatesAutoresizingMaskIntoConstraints = false
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
        func slider(_ text: String, value: Double, lower: Double, upper: Double,
                    group: UIStackView, change: @escaping (Double) -> Void) {
            let container = UIView()
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
            let title = UILabel(); title.text = localized(text); title.numberOfLines = 2
            title.font = .preferredFont(forTextStyle: .body); title.adjustsFontForContentSizeCategory = true
            title.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(title)
            let control = UISlider(); control.minimumValue = Float(lower); control.maximumValue = Float(upper)
            control.value = Float(value); control.accessibilityLabel = localized(text)
            control.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(control)
            let valueLabel = UILabel(); valueLabel.textAlignment = .right
            valueLabel.font = .preferredFont(forTextStyle: .footnote); valueLabel.textColor = .secondaryLabel
            valueLabel.text = "\(Int((value * 100).rounded()))%"
            valueLabel.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(valueLabel)
            NSLayoutConstraint.activate([
                title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
                title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
                title.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
                control.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
                control.trailingAnchor.constraint(equalTo: valueLabel.leadingAnchor, constant: -10),
                control.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
                control.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
                valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
                valueLabel.centerYAnchor.constraint(equalTo: control.centerYAnchor),
                valueLabel.widthAnchor.constraint(equalToConstant: 42)
            ])
            control.addAction(UIAction { [weak valueLabel, weak control] _ in
                guard let control else { return }
                let current = Double(control.value)
                valueLabel?.text = "\(Int((current * 100).rounded()))%"
                valueLabel?.accessibilityValue = valueLabel?.text
                change(current)
            }, for: .valueChanged)
            append(container, to: group)
        }

        let typing = card("Ввод")
        toggle("Автозамена", value: settings.autoCorrection, group: typing) { [weak self] value in
            self?.settings.autoCorrection = value; self?.settings.saveKeyboardOverrides()
        }
        toggle("Разрешить нецензурные слова в подсказках и автозамене", value: settings.allowProfanitySuggestions, group: typing) { [weak self] value in
            self?.settings.allowProfanitySuggestions = value; self?.settings.saveKeyboardOverrides(); self?.refreshSuggestions()
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
        let prediction = card("Предиктивный ввод")
        toggle("Предсказание следующего слова", value: settings.nextWordPrediction, group: prediction) { [weak self] value in
            guard let self else { return }
            self.settings.nextWordPrediction = value; self.settings.saveKeyboardOverrides(); self.refreshSuggestions()
        }
        toggle("Локальное обучение подсказок", value: settings.personalizationEnabled, group: prediction) { [weak self] value in
            guard let self else { return }
            self.settings.personalizationEnabled = value; self.settings.saveKeyboardOverrides(); self.refreshSuggestions()
        }
        let predictionNote = UILabel(); predictionNote.numberOfLines = 0
        predictionNote.font = .preferredFont(forTextStyle: .footnote); predictionNote.textColor = .secondaryLabel
        predictionNote.text = localized("Обучение хранит только короткие агрегированные счётчики локально. Сообщения, пароли и история набора не сохраняются; полный доступ не требуется.")
        content.addArrangedSubview(predictionNote)
        let resetPrediction = UIButton(type: .system)
        resetPrediction.setTitle(localized("Сбросить адаптацию подсказок"), for: .normal)
        resetPrediction.contentHorizontalAlignment = .leading
        resetPrediction.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        resetPrediction.addAction(UIAction { [weak self, weak resetPrediction] _ in
            guard let self else { return }
            self.predictionProfile.reset(); self.refreshSuggestions()
            resetPrediction?.setTitle(self.localized("Адаптация подсказок сброшена"), for: .normal)
        }, for: .touchUpInside)
        append(resetPrediction, to: prediction)
        let feedbackCard = card("Тактильный отклик")
        let haptics = UISegmentedControl(items: HapticChoice.allCases.map { localized($0.title) })
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
        slider("Высота клавиатуры", value: settings.keyboardHeightScale, lower: 0.92, upper: 1.10, group: appearance) { [weak self] value in
            guard let self else { return }
            self.settings.keyboardHeightScale = KeyboardSizing.heightScale(value)
            self.settings.saveKeyboardOverrides(); self.applyKeyboardHeight()
        }
        slider("Визуальная ширина клавиш", value: settings.visualKeyWidthScale, lower: 0.84, upper: 1.12, group: appearance) { [weak self] value in
            guard let self else { return }
            self.settings.visualKeyWidthScale = KeyboardSizing.visualWidthScale(value)
            self.settings.saveKeyboardOverrides()
            self.keyPlane.visualWidthScale = CGFloat(self.settings.visualKeyWidthScale)
            self.keyPlane.setNeedsLayout(); self.keyPlane.layoutIfNeeded()
        }
        toggle("Отображение символа при нажатии", value: settings.showKeyPreview, group: appearance) { [weak self] value in
            guard let self else { return }
            self.settings.showKeyPreview = value; self.settings.saveKeyboardOverrides()
            if !value { self.hideKeyPreview() }
        }
        toggle("Заменить глобус на эмодзи", value: settings.emojiKeyEnabled, group: appearance) { [weak self] value in
            self?.settings.emojiKeyEnabled = value; self?.settings.saveKeyboardOverrides()
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
        calibrationNote.text = localized("Локальное обучение меняет центр и ширину зоны касания по обезличенным агрегатам. Буквы, сообщения, пароли и история координат не сохраняются. Сброс охватывает все ориентации.")
        content.addArrangedSubview(calibrationNote)
        let clearCalibration = UIButton(type: .system); clearCalibration.setTitle(localized("Сбросить адаптацию касаний"), for: .normal)
        clearCalibration.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        clearCalibration.addAction(UIAction { [weak self, weak clearCalibration] _ in
            self?.resetTouchCalibration(); clearCalibration?.setTitle(self?.localized("Адаптация сброшена"), for: .normal)
        }, for: .touchUpInside)
        append(clearCalibration, to: accuracy)
        let dictionaryCard = card("Личный словарь")
        let dictionary = UIButton(type: .system)
        var dictionaryStyle = UIButton.Configuration.plain()
        dictionaryStyle.title = localized("Замены и исключения")
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
        note.text = localized("Изменения сохраняются сразу. «Готово» применяет оформление. Тактильный отклик зависит от iOS и устройства.")
        content.addArrangedSubview(note)
        let reset = UIButton(type: .system)
        var resetStyle = UIButton.Configuration.plain()
        resetStyle.title = localized("Сбросить локальные настройки"); resetStyle.baseForegroundColor = .systemRed
        resetStyle.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)
        reset.configuration = resetStyle; reset.titleLabel?.numberOfLines = 0
        reset.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        reset.addAction(UIAction { [weak self] _ in
            KeyboardSettings.clearKeyboardOverrides(); self?.reloadSettings()
        }, for: .touchUpInside)
        content.addArrangedSubview(reset)
        let preservation = UILabel(); preservation.text = localized("Личный словарь при сбросе сохранится.")
        preservation.numberOfLines = 0; preservation.textColor = .secondaryLabel
        preservation.font = .preferredFont(forTextStyle: .footnote); preservation.adjustsFontForContentSizeCategory = true
        content.addArrangedSubview(preservation)

        let languages = card("Языки ввода · минимум один")
        for language in KeyboardLanguage.allCases {
            languageSwitches[language] = toggle(language.title, value: settings.languages.contains(language), group: languages) { [weak self] enabled in
                guard let self else { return }
                self.settings.languages = EnabledKeyboardLanguages.setting(language, enabled: enabled, in: self.settings.languages)
                self.settings.saveKeyboardOverrides()
                if !self.settings.languages.contains(self.state.language), let first = self.settings.languages.first {
                    self.state.language = first; KeyboardSettings.rememberLanguage(first); self.prewarmLexicon()
                }
                self.updateLanguageSwitches()
            }
        }
        updateLanguageSwitches()

        let locale = card("Язык интерфейса")
        let localeControl = UISegmentedControl(items: InterfaceLanguage.allCases.map(\.shortTitle))
        localeControl.selectedSegmentIndex = InterfaceLanguage.allCases.firstIndex(of: settings.interfaceLanguage) ?? 0
        localeControl.addAction(UIAction { [weak self, weak localeControl] _ in
            guard let self, let localeControl, InterfaceLanguage.allCases.indices.contains(localeControl.selectedSegmentIndex) else { return }
            self.settings.interfaceLanguage = InterfaceLanguage.allCases[localeControl.selectedSegmentIndex]
            self.settings.saveKeyboardOverrides()
        }, for: .valueChanged)
        segmented("Язык интерфейса", control: localeControl, group: locale)

        rows.isHidden = true; settingsPanel = panel
        UIAccessibility.post(notification: .screenChanged, argument: done)
    }

    private func spaceTitle() -> String { "‹ " + state.language.title + " ›" }
    private func updateLanguageSwitches() {
        for (language, control) in languageSwitches {
            let enabled = settings.languages.contains(language)
            control.setOn(enabled, animated: true)
            control.isEnabled = !enabled || settings.languages.count > 1
        }
    }
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
        if pendingInput.deferIfBusy(.language(direction)) { return }
        guard !cursorMode, settingsPanel == nil, settings.languages.count > 1 else { return }
        state.cycleLanguage(enabled: settings.languages, direction: direction)
        KeyboardSettings.rememberLanguage(state.language)
        prewarmLexicon()
        suppressedCorrection = nil; performFeedback(); rebuild(preservingInput: drainingInput)
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
        spaceButton?.accessibilityValue = active ? localized("Управление курсором") : state.language.title
        if active {
            for button in keyPlane.keyViews where button is TextKeyButton { button.cancelTracking(with: nil) }
            dismissPopup(); stopDeleting(); performFeedback()
        }
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
    private var needsToolbar: Bool { true } // Keep suggestions and the in-keyboard emoji-search input available.
    private func scheduleSettingsHint(for button: KeyButton) {
        hideKeyPreview()
        let task = DispatchWorkItem { [weak self, weak button] in
            guard let self, let button, self.settingsPanel == nil, !self.cursorMode,
                  let layout = KeyPreviewLayout.make(keyFrame: button.convert(button.bounds, to: self.view), availableBounds: self.view.bounds) else { return }
            self.previewGeneration &+= 1; self.previewKey = button
            self.keyPreview.showSymbol(layout: layout, name: "gearshape.fill", fill: self.theme.key, ink: self.theme.foreground)
        }
        settingsHintTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.08, settings.holdDelay - 0.12), execute: task)
    }
    private func deleteWord(force: Bool = false) {
        if pendingInput.deferIfBusy(.deleteWord) { return }
        let restoreSuffix = force ? "" : deleteSwipeRestoreSuffix
        deleteSwipeRestoreSuffix = ""
        guard (force || settings.swipeDeleteWord), lexiconEditing == nil, !cursorMode else { return }
        completedWord = nil
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
        if force { deletionUndo = nil }
        else { deletionUndo = TextDeletionUndo(deletedText: deleted + restoreSuffix, before: remaining, after: after, document: document) }
        performFeedback(); suggestionSignature = nil; updateContext()
    }

    private func saveCurrentWordToPersonalDictionary(_ word: String) {
        guard textDocumentProxy.isSecureTextEntry != true,
              (3...64).contains(word.count), word.allSatisfy(\.isLetter),
              let dictionaryCheck = OfflineLexicon.preparedCheck(word, language: state.language),
              !dictionaryCheck.known else { return }
        settings.personalLexicon.addKnownWord(word)
        settings.saveKeyboardOverrides()
        suggestionSignature = nil
        refreshSuggestions()
    }
    private func restoreDeletedWord() {
        guard let undo = deletionUndo,
              undo.matches(before: textDocumentProxy.documentContextBeforeInput, after: textDocumentProxy.documentContextAfterInput, document: String(describing: textDocumentProxy.documentIdentifier), hasSelection: !(textDocumentProxy.selectedText ?? "").isEmpty) else { deletionUndo = nil; updateContext(); return }
        deletionUndo = nil; textDocumentProxy.insertText(undo.deletedText)
        lastSpace = nil; suggestionSignature = nil; updateContext()
    }
    private var currentDraft: String { lexiconEditing == .replacement ? draftValue : draftSource }
    private var editorPrompt: String {
        switch lexiconEditing { case .source: return localized("Сокращение: "); case .replacement: return localized("Замена: "); case .exception: return localized("Не исправлять: "); case nil: return "" }
    }
    private func configureEditorBar() {
        clear(toolbar)
        let cancel = UIButton(type: .system); cancel.setTitle("✕", for: .normal); cancel.tintColor = theme.foreground
        cancel.addAction(UIAction { [weak self] _ in self?.finishLexiconEditing(cancelled: true) }, for: .touchUpInside)
        let label = UILabel(); label.font = .systemFont(ofSize: 13); label.textColor = theme.foreground
        label.text = editorPrompt + currentDraft + "▏"; label.lineBreakMode = .byTruncatingHead; draftLabel = label
        let done = UIButton(type: .system); done.setTitle(lexiconEditing == .source ? localized("Далее") : "✓", for: .normal); done.tintColor = theme.foreground
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
        state.symbols = false; state.emoji = false; rebuild(); updateContext()
    }
    private func finishLexiconEditing(cancelled: Bool) {
        if !cancelled {
            let source = draftSource.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty, source.allSatisfy({ $0.isLetter }) else { draftLabel?.text = localized("Введите одно слово буквами"); return }
            if lexiconEditing == .source { lexiconEditing = .replacement; rebuild(); updateContext(); return }
            if lexiconEditing == .exception { settings.personalLexicon.excludedWords.append(source) }
            else {
                let value = draftValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { draftLabel?.text = localized("Введите замену"); return }
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
        action(localized("Готово")) { [weak self] in self?.rebuild(); self?.updateContext() }
        action(localized("＋ Добавить замену")) { [weak self] in self?.beginLexiconEditing(.source) }
        action(localized("＋ Не исправлять слово")) { [weak self] in self?.beginLexiconEditing(.exception) }
        let note = UILabel(); note.numberOfLines = 0; note.font = .systemFont(ofSize: 12); note.textColor = .secondaryLabel
        note.text = localized("Записи хранятся только на устройстве. При добавлении используйте клавиши ниже; текст в приложении не изменяется. Нажмите запись для удаления.")
        stack.addArrangedSubview(note)
        for (source, target) in settings.personalLexicon.replacements.sorted(by: { $0.key < $1.key }) {
            action("\(source) → \(target)   ×") { [weak self] in self?.settings.personalLexicon.replacements.removeValue(forKey: source); self?.settings.saveKeyboardOverrides(); self?.showLexiconPanel() }
        }
        for word in settings.personalLexicon.knownWords {
            action(localized("Пользовательское слово: ") + word + "   ×") { [weak self] in
                guard let self else { return }
                self.settings.personalLexicon.knownWords.removeAll { $0.caseInsensitiveCompare(word) == .orderedSame }
                self.settings.saveKeyboardOverrides(); self.showLexiconPanel()
            }
        }
        for word in settings.personalLexicon.excludedWords.sorted() {
            action(localized("Не исправлять: ") + "\(word)   ×") { [weak self] in self?.settings.personalLexicon.excludedWords.removeAll { $0 == word }; self?.settings.saveKeyboardOverrides(); self?.showLexiconPanel() }
        }
    }
    private var inputContext: InputContextSnapshot {
        InputContextSnapshot(before: textDocumentProxy.documentContextBeforeInput,
                             after: textDocumentProxy.documentContextAfterInput,
                             document: String(describing: textDocumentProxy.documentIdentifier),
                             hasSelection: !(textDocumentProxy.selectedText ?? "").isEmpty,
                             fieldIsEmpty: !textDocumentProxy.hasText)
    }
    private func invalidatePendingInput() {
        if let expected = pendingInput.context, !expected.matches(inputContext) { pendingInput.cancel() }
        if let word = completedWord, !word.matches(inputContext) { completedWord = nil }
    }
    private func preservingActiveStroke(_ action: () -> Void) {
        let before = inputContext
        let active = glideSnapshot
        action()
        // A preceding queued word can finish while the next finger is moving.
        // Advance that stroke's snapshot only for our own verified insertion.
        if let active, glideSnapshot != nil, active.0.matches(before) {
            glideSnapshot = (inputContext, active.1)
        }
    }
    private func drainInput() {
        guard !drainingInput else { return }
        drainingInput = true
        defer { drainingInput = false }
        while let action = pendingInput.next() {
            preservingActiveStroke {
                switch action {
                case .text(let text): insert(text)
                case .backspace(let atomic): deleteOnce(allowGlideWord: atomic)
                case .deleteWord: deleteWord()
                case .shift: shiftTapped()
                case .symbols: toggleSymbols()
                case .emoji: toggleEmojiKeyboard()
                case .language(let direction): cycleLanguage(direction)
                case .glide(let request): decodeGlide(request)
                case .suggestion(let word, let prefix): accept(word, prefix: prefix)
                }
            }
        }
    }
    private func decodeGlide(_ request: GlideRequest) {
        guard settings.glideTyping, !state.symbols, !state.emoji, !cursorMode, settingsPanel == nil,
              lexiconEditing == nil, textAllowsAutomation, request.language == state.language,
              inputContext.isUsable else { return }
        let context = inputContext
        let token = pendingInput.begin(in: context)
        let lexicon = effectivePersonalLexicon
        let extras = lexicon.knownWords + Array(lexicon.replacements.values) + lexicon.excludedWords
        glideDecodeTask?.cancel()
        glideDecodeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let decoded: [String]
            do {
                decoded = try await self.glideDecoder.decode(points: request.points, keyCenters: request.centers,
                                                             language: request.language, extraWords: extras)
            } catch is CancellationError {
                return
            } catch {
                return
            }
            guard !Task.isCancelled, self.pendingInput.token == token else { return }
                guard self.view.window != nil, self.settings.glideTyping, !self.state.symbols, !self.state.emoji,
                      !self.cursorMode, self.settingsPanel == nil, self.lexiconEditing == nil,
                      self.textAllowsAutomation, self.state.language == request.language else {
                    self.pendingInput.cancel(); return
                }
                guard self.pendingInput.finish(token: token, in: self.inputContext) else { return }
                self.preservingActiveStroke { self.commitGlide(decoded, context: context) }
                self.drainInput()
        }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === glidePan, settings.glideTyping, !state.symbols, !state.emoji, !cursorMode, settingsPanel == nil, lexiconEditing == nil, textAllowsAutomation else { return false }
        // Let the first contact keep glide recognition. If another finger
        // lands on a different letter while it is active, keep that new tap
        // with its own UIButton instead of letting the pan cancel both views.
        if keyPlane.hasActiveTextContacts && !keyPlane.ownsTextContact(touch) { return false }
        var target = touch.view
        while let candidate = target {
            if letterButtons.contains(where: { $0.0 === candidate }) { return true }
            target = candidate.superview
        }
        return false
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === glidePan else { return true }
        return settings.glideTyping && !state.symbols && !state.emoji && !cursorMode && settingsPanel == nil && lexiconEditing == nil && textAllowsAutomation
    }
    @objc private func glideChanged(_ pan: GlideTouchRecognizer) {
        switch pan.state {
        case .began:
            hideKeyPreview(); dismissPopup(); stopDeleting(); lastSpace = nil; deletionUndo = nil
            glideSnapshot = (inputContext, state.language)
            trailSamples.removeAll(keepingCapacity: true)
            appendTrailPoint(pan.points.last ?? pan.startPoint)
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                DispatchQueue.main.async { [weak self] in self?.drawGlide() }
            }
            trailTimer?.invalidate(); trailTimer = timer; RunLoop.main.add(timer, forMode: .common)
        case .changed:
            if let point = pan.points.last { appendTrailPoint(point) }
        case .ended:
            guard settings.glideTyping, !state.symbols, !state.emoji, !cursorMode, settingsPanel == nil, lexiconEditing == nil, textAllowsAutomation,
                  let snapshot = glideSnapshot, snapshot.0.matches(inputContext), snapshot.1 == state.language else { resetGlidePresentation(); return }
            let points = pan.points
            if let model = keyPlane.recognizer, GlideActivation.isShortStroke(points, keyPitch: model.geometry.pitch),
               let end = points.last, let result = model.resolve(view.convert(end, to: keyPlane)),
               let character = model.geometry.keys[result.first.keyIndex].role.character {
                resetGlidePresentation(); insert(character); return
            }
            var centers: [String: CGPoint] = [:]
            if let geometry = keyPlane.recognizer?.geometry {
                for key in geometry.keys {
                    if let letter = key.role.character, letter.allSatisfy(\.isLetter) {
                        centers[letter] = keyPlane.convert(key.center, to: view)
                    }
                }
            }
            resetGlidePresentation()
            pendingInput.enqueue(.glide(GlideRequest(points: points, centers: centers, language: snapshot.1)))
            drainInput()
        case .cancelled, .failed: resetGlidePresentation()
        default: break
        }
    }
    private func commitGlide(_ decoded: [String], context: InputContextSnapshot) {
        guard let best = decoded.first else {
            clear(suggestions); suggestionSignature = "glide-miss"
            let label = UILabel(); label.text = localized("Нет совпадений"); label.textColor = .secondaryLabel
            label.textAlignment = .center; label.font = .systemFont(ofSize: 13); suggestions.addArrangedSubview(label)
            return
        }
        synchronizeCapitalization()
        let inserted = state.insertedWord(best)
        let prefix = GlideWordSpacing.leadingSpace(after: context.before)
        correctionUndo = nil; suppressedCorrection = nil
        let text = prefix + inserted + " "
        textDocumentProxy.insertText(text)
        learnWord(best, after: context.before ?? "", language: state.language)
        completedWord = CompletedWordInsertion(origin: .glide, insertedText: text, context: inputContext)
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
        let cutoff = ProcessInfo.processInfo.systemUptime - 0.095
        trailSamples.removeAll { $0.time < cutoff }
        // Also cap spatial length: a fast sweep must not leave a long ribbon.
        let maximumLength = max(44, (keyPlane.recognizer?.geometry.pitch.width ?? 32) * 2.2)
        var length: CGFloat = 0
        var firstIndex = max(0, trailSamples.count - 1)
        while firstIndex > 0 {
            let a = trailSamples[firstIndex - 1].point, b = trailSamples[firstIndex].point
            let segment = hypot(b.x - a.x, b.y - a.y)
            if length + segment > maximumLength {
                let remaining = maximumLength - length
                let fraction = segment > 0 ? remaining / segment : 0
                trailSamples[firstIndex - 1].point = CGPoint(x: b.x + (a.x - b.x) * fraction, y: b.y + (a.y - b.y) * fraction)
                firstIndex -= 1; break
            }
            length += segment; firstIndex -= 1
        }
        if firstIndex > 0 { trailSamples.removeFirst(firstIndex) }
        let path = UIBezierPath()
        if let first = trailSamples.first { path.move(to: first.point); for sample in trailSamples.dropFirst() { path.addLine(to: sample.point) } }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        glideTrail.frame = view.bounds; glideTrail.strokeColor = theme.foreground.withAlphaComponent(0.42).cgColor; glideTrail.path = path.cgPath
        CATransaction.commit()
    }
    private func cancelGlide() {
        glideDecodeTask?.cancel(); glideDecodeTask = nil
        pendingInput.cancel()
        resetGlidePresentation()
    }
    private func resetGlidePresentation() {
        glideSnapshot = nil
        glidePan.cancelCurrentTouch()
        trailTimer?.invalidate(); trailTimer = nil; trailSamples.removeAll(keepingCapacity: true); glideTrail.path = nil
    }
    private func acceptGlide(_ index: Int) {
        guard !pendingInput.isBusy else { return }
        guard glideWords.indices.contains(index), let undo = glideUndo, undoMatches(undo) else { glideWords = []; glideUndo = nil; updateContext(); return }
        let word = glideWords[index]
        let prefix = completedWord?.insertedText.hasPrefix(" ") == true ? " " : ""
        let previousContext = undo.contextBeforeReplacement() ?? ""
        for _ in (undo.replacement + " ") { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(word + " ")
        learnWord(word, after: previousContext, language: state.language)
        completedWord = CompletedWordInsertion(origin: .glide, insertedText: prefix + word + " ", context: inputContext)
        if let before = textDocumentProxy.documentContextBeforeInput {
            glideUndo = CorrectionUndo(original: "", replacement: word, delimiter: " ", before: before, after: textDocumentProxy.documentContextAfterInput, document: String(describing: textDocumentProxy.documentIdentifier))
        }
        suggestionSignature = nil; updateContext()
    }
    private func returnTitle() -> String {
        switch textDocumentProxy.returnKeyType ?? .default {
        case .go: return "Go"
        case .search: return localized("Поиск")
        case .send: return localized("Отпр.")
        case .done: return localized("Готово")
        case .next: return localized("Далее")
        default: return localized("Клавиша ввода")
        }
    }
    private func insert(_ text: String) {
        if pendingInput.deferIfBusy(.text(text)) { return }
        if emojiSearchActive {
            if text == "\n" {
                if let first = EmojiSearch.search(emojiSearchQuery, in: emojiItems, limit: 1).first {
                    selectEmojiSearchResult(first.emoji)
                }
                return
            }
            emojiSearchQuery.append(text)
            refreshEmojiSearchResults()
            return
        }
        if lexiconEditing != nil { editLexicon(text); return }
        synchronizeCapitalization()
        let trim = completedWord?.spaceDeletionCount(before: text, in: inputContext) ?? 0
        completedWord = nil
        deletionUndo = nil; glideWords = []; glideUndo = nil
        if trim > 0 {
            lastSpace = nil; correctionUndo = nil
            for _ in 0..<trim { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(state.inserted(text)); updateContext(); return
        }
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
        let beforeInput = textDocumentProxy.documentContextBeforeInput
        let automaticSpace = text.allSatisfy(\.isLetter) && textAllowsAutomation
            ? PunctuationSpacing.prefixBeforeLetter(after: beforeInput) : ""
        if !automaticSpace.isEmpty {
            state.synchronize(context: (beforeInput ?? "") + automaticSpace,
                              autoCapitalization: settings.autoCapitalization && textAllowsAutomation)
        }
        textDocumentProxy.insertText(automaticSpace + state.inserted(text))
        if text == " " { rememberSpace() }
        if [" ", "\n", ".", ",", "!", "?", ":", ";"].contains(text) { learnCompletedWord(endingWith: text) }
        updateContext()
    }
    private var textAllowsAutomation: Bool {
        let kind: KeyboardInputFieldKind
        switch textDocumentProxy.keyboardType ?? .default {
        case .emailAddress: kind = .email
        case .URL: kind = .url
        case .phonePad, .namePhonePad: kind = .phone
        case .numberPad: kind = .number
        case .decimalPad: kind = .decimal
        case .asciiCapableNumberPad: kind = .asciiNumber
        case .webSearch: kind = .webSearch
        case .twitter: kind = .social
        default: kind = .standard
        }
        return TextAutomationPolicy.allowsCorrection(in: kind, isSecure: textDocumentProxy.isSecureTextEntry == true)
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
    private func learnWord(_ word: String, after previousContext: String, language: KeyboardLanguage) {
        guard settings.personalizationEnabled, textAllowsAutomation,
              textDocumentProxy.isSecureTextEntry != true,
              (1...24).contains(word.count), word.allSatisfy(\.isLetter),
              !SupplementalVocabulary.isProfanity(word, language: language) || settings.allowProfanitySuggestions else { return }
        let store = predictionProfile
        let lexiconRepository = hasFullAccess ? personalLexiconRepository : nil
        predictionQueue.async {
            store.observe(context: previousContext, nextWord: word, language: language)
            try? lexiconRepository?.learn(word)
        }
    }
    private func learnCompletedWord(endingWith delimiter: String) {
        guard textDocumentProxy.isSecureTextEntry != true,
              let after = textDocumentProxy.documentContextBeforeInput, after.hasSuffix(delimiter) else { return }
        let content = String(after.dropLast(delimiter.count))
        guard let word = personalWord(in: content) else { return }
        learnWord(word, after: String(content.dropLast(word.count)), language: state.language)
    }
    private func applyCorrection(delimiter: String) -> Bool {
        guard settings.autoCorrection, textAllowsAutomation, (textDocumentProxy.selectedText ?? "").isEmpty,
              textDocumentProxy.autocorrectionType != .no,
              let context = textDocumentProxy.documentContextBeforeInput,
              let word = personalWord(in: context) else { return false }
        guard suppressedCorrection != word,
              let replacement = textService.replacement(for: word, language: state.language,
                                                        personalLexicon: effectivePersonalLexicon,
                                                        includeProfanity: settings.allowProfanitySuggestions,
                                                        languageModel: settings.personalizationEnabled && textDocumentProxy.isSecureTextEntry != true
                                                            ? predictionProfile.snapshot() : PersonalNGramModel(),
                                                        previousContext: String(context.dropLast(word.count))),
              replacement != word else { return false }
        guard textDocumentProxy.documentContextBeforeInput == context, (textDocumentProxy.selectedText ?? "").isEmpty else { return false }
        correctionUndo = nil
        for _ in word { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(replacement + delimiter)
        _ = state.inserted(delimiter)
        learnWord(replacement, after: String(context.dropLast(word.count)), language: state.language)
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
        if pendingInput.deferIfBusy(.shift) { return }
        if state.symbols { state.symbolPage = state.symbolPage.next; rebuild(preservingInput: drainingInput); return }
        state.tapShift(at: ProcessInfo.processInfo.systemUptime); refreshLabels()
    }
    private func toggleSymbols() {
        if pendingInput.deferIfBusy(.symbols) { return }
        state.emoji = false
        state.symbols.toggle()
        if state.symbols { state.symbolPage = .numbers }
        rebuild(preservingInput: drainingInput)
    }
    private func toggleEmojiKeyboard() {
        if pendingInput.deferIfBusy(.emoji) { return }
        if emojiSearchActive {
            emojiSearchActive = false
            emojiSearchQuery = ""
            state.emoji = true
            state.symbols = false
            rebuild(preservingInput: drainingInput)
            return
        }
        state.emoji.toggle()
        if state.emoji { state.symbols = false }
        rebuild(preservingInput: drainingInput)
    }
    private func leaveEmojiKeyboard() {
        guard state.emoji else { return }
        toggleEmojiKeyboard()
    }
    private func refreshLabels() {
        let uppercase = !state.symbols && !state.emoji && state.shift != .off
        if renderedLetterCase != uppercase {
            for (button, key) in letterButtons {
                let value = state.symbols || state.emoji || state.shift == .off ? key : key.uppercased()
                if button.title(for: .normal) != value { button.setTitle(value, for: .normal); button.accessibilityLabel = value }
            }
            renderedLetterCase = uppercase
        }
        if state.emoji {
            if renderedShift != "emoji-abc" {
                shiftButton?.setImage(nil, for: .normal)
                shiftButton?.setTitle("ABC", for: .normal)
                renderedShift = "emoji-abc"
            }
        } else if state.symbols {
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
        shiftButton?.accessibilityValue = state.emoji ? localized("Эмодзи") : (state.symbols ? (state.symbolPage == .numbers ? "123" : "#*=") : (state.shift == .locked ? "Caps Lock" : (state.shift == .once ? localized("Включён") : localized("Выключен"))))
    }
    private func stopDeleting() { deleteButton?.cancelInteraction() }
    private func beginBackspacePress() {
        if pendingInput.isBusy {
            // A word-decoder must never hold the first delete. Invalidate its
            // token, retain queued key events in order, and drain them before
            // applying this backspace on the main thread.
            pendingInput.invalidateWorkPreservingCommands()
            pendingInput.removeQueued { action in
                if case .glide = action { return true }
                return false
            }
            resetGlidePresentation()
            drainInput()
        }
        let before = textDocumentProxy.documentContextBeforeInput
        deleteSwipeRestoreSuffix = ""
        performFeedback()
        deleteOnce()
        if let before, let after = textDocumentProxy.documentContextBeforeInput {
            let beforeCharacters = Array(before), afterCharacters = Array(after)
            if afterCharacters.count < beforeCharacters.count,
               Array(beforeCharacters.prefix(afterCharacters.count)) == afterCharacters {
                deleteSwipeRestoreSuffix = String(beforeCharacters.dropFirst(afterCharacters.count))
            }
        }
    }
    private func deleteOnce(allowGlideWord: Bool = true) {
        if emojiSearchActive {
            if !emojiSearchQuery.isEmpty { emojiSearchQuery.removeLast() }
            refreshEmojiSearchResults()
            return
        }
        if pendingInput.deferIfBusy(.backspace(allowGlideWord)) { return }
        let word = completedWord
        let atomicCount = allowGlideWord ? word?.deletionCount(in: inputContext) : nil
        completedWord = nil
        lastSpace = nil; deletionUndo = nil; glideWords = []; glideUndo = nil
        if lexiconEditing != nil { editLexiconDelete(); return }
        if let atomicCount, let word {
            correctionUndo = nil; suppressedCorrection = nil
            for _ in 0..<atomicCount { textDocumentProxy.deleteBackward() }
            if let before = textDocumentProxy.documentContextBeforeInput {
                deletionUndo = TextDeletionUndo(deletedText: word.insertedText, before: before,
                                                 after: textDocumentProxy.documentContextAfterInput,
                                                 document: String(describing: textDocumentProxy.documentIdentifier))
            }
        } else if let undo = correctionUndo, undoMatches(undo) {
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
    private func synchronizeCapitalization() {
        guard lexiconEditing == nil else { return }
        state.synchronize(context: textDocumentProxy.documentContextBeforeInput,
                          autoCapitalization: settings.autoCapitalization && textAllowsAutomation,
                          fieldIsEmpty: !textDocumentProxy.hasText)
    }
    private func updateContext() {
        guard !cursorMode else { return }
        if lexiconEditing != nil {
            state.synchronize(context: currentDraft, autoCapitalization: true)
            backspaceEngine.synchronizeBuffer(contextBeforeInput: currentDraft)
            draftLabel?.text = editorPrompt + currentDraft + "▏"
            refreshLabels(); return
        }
        synchronizeCapitalization()
        backspaceEngine.synchronizeBuffer(contextBeforeInput: textDocumentProxy.documentContextBeforeInput)
        refreshLabels(); refreshSuggestions()
    }
    private func refreshSuggestions() {
        pendingPredictionRequest?.cancel(); pendingPredictionRequest = nil
        predictionGeneration &+= 1
        let generation = predictionGeneration
        suggestions.isUserInteractionEnabled = true
        guard lexiconEditing == nil else { return }
        if emojiSearchActive {
            refreshEmojiSearchResults()
            return
        }
        if state.emoji {
            if suggestionSignature != "emoji-layout" { clear(suggestions); suggestionSignature = "emoji-layout" }
            return
        }
        if let undo = deletionUndo, undo.matches(before: textDocumentProxy.documentContextBeforeInput, after: textDocumentProxy.documentContextAfterInput, document: String(describing: textDocumentProxy.documentIdentifier), hasSelection: !(textDocumentProxy.selectedText ?? "").isEmpty) {
            if suggestionSignature != "undo-delete" {
                clear(suggestions); suggestionSignature = "undo-delete"
                let button = makeSuggestionButton(localized("Вернуть слово")); button.titleLabel?.font = .systemFont(ofSize: 14)
                button.addAction(UIAction { [weak self] _ in self?.restoreDeletedWord() }, for: .touchUpInside); suggestions.addArrangedSubview(button)
            }
            return
        }
        if !glideWords.isEmpty, let undo = glideUndo, undoMatches(undo) {
            let signature = "glide:" + glideWords.joined(separator: "|")
            if suggestionSignature != signature {
                clear(suggestions); suggestionSignature = signature
                for (index, word) in glideWords.enumerated() {
                    let button = makeSuggestionButton(word); button.titleLabel?.font = .systemFont(ofSize: 15)
                    button.addAction(UIAction { [weak self] _ in self?.acceptGlide(index) }, for: .touchUpInside); suggestions.addArrangedSubview(button)
                }
            }
            return
        }
        let context = textDocumentProxy.documentContextBeforeInput
        let prefix = context.map { LocalSuggestionProvider.trailingWord(in: String($0.suffix(64))) } ?? ""
        let language = state.language
        let personalLexicon = effectivePersonalLexicon
        let suggestionsEnabled = settings.suggestions
        let personalizationEnabled = settings.personalizationEnabled
        let allowProfanity = settings.allowProfanitySuggestions
        let nextWordEnabled = settings.nextWordPrediction && textAllowsAutomation
        let isSecure = textDocumentProxy.isSecureTextEntry == true
        let shouldUsePersonalization = personalizationEnabled && !isSecure
        let boundedContext = String((context ?? "").suffix(192))
        let shift = state.shift
        let request = PredictionRequest()
        pendingPredictionRequest = request
        pendingPrefix = nil; suggestionWords.removeAll(keepingCapacity: true)
        suggestions.isUserInteractionEnabled = false
        predictionQueue.async { [weak self] in
            guard let self, !request.isCancelled else { return }
            let profile = shouldUsePersonalization ? self.predictionProfile.snapshot() : PersonalNGramModel()
            let result: PredictionResult
            if suggestionsEnabled && !isSecure {
                result = self.predictionEngine.predict(context: boundedContext, language: language,
                                                       personalLexicon: personalLexicon, model: profile,
                                                       includeProfanity: allowProfanity,
                                                       nextWordPrediction: nextWordEnabled, limit: 3)
            } else { result = PredictionResult(prefix: prefix, words: []) }
            let canOfferSave = result.words.isEmpty && suggestionsEnabled && !isSecure &&
                (3...64).contains(result.prefix.count) && result.prefix.allSatisfy(\.isLetter) &&
                !SupplementalVocabulary.isProfanity(result.prefix, language: language) &&
                !personalLexicon.containsKnownWord(result.prefix) &&
                OfflineLexicon.preparedCheck(result.prefix, language: language)?.known == false
            let words = result.words.map { candidate -> String in
                if result.prefix.isEmpty && shift != .off {
                    return shift == .locked ? candidate.uppercased() : candidate.capitalized
                }
                guard result.prefix.first?.isUppercase == true else { return candidate }
                return shift == .locked || (result.prefix.allSatisfy(\.isUppercase) && result.prefix.count > 1)
                    ? candidate.uppercased() : candidate.capitalized
            }
            guard !request.isCancelled else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, !request.isCancelled, self.predictionGeneration == generation else { return }
                guard self.state.language == language, !self.state.emoji,
                      self.textDocumentProxy.documentContextBeforeInput == context,
                      (self.textDocumentProxy.selectedText ?? "").isEmpty,
                      self.textDocumentProxy.isSecureTextEntry == isSecure else {
                    self.pendingPredictionRequest = nil
                    self.suggestions.isUserInteractionEnabled = true
                    self.updateContext()
                    return
                }
                self.pendingPredictionRequest = nil
                self.renderStandardSuggestions(words, prefix: result.prefix, language: language,
                                               canOfferSave: canOfferSave)
            }
        }
    }
    private func renderStandardSuggestions(_ words: [String], prefix: String,
                                           language: KeyboardLanguage, canOfferSave: Bool) {
        pendingPrefix = words.isEmpty ? nil : prefix
        suggestionWords = words
        suggestions.isUserInteractionEnabled = true
        let signature = language.rawValue + "|" + prefix + "|" + words.joined(separator: "|") + (canOfferSave ? "|save" : "")
        guard suggestionSignature != signature else { return }
        suggestionSignature = signature
        if words.isEmpty {
            clear(suggestions)
            if canOfferSave {
                let button = makeSuggestionButton("＋  " + localized("Добавить в личный словарь") + "  «" + prefix + "»")
                button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
                button.accessibilityHint = localized("Слово будет сохранено только на этом устройстве")
                button.addAction(UIAction { [weak self] _ in self?.saveCurrentWordToPersonalDictionary(prefix) }, for: .touchUpInside)
                suggestions.addArrangedSubview(button)
            }
            return
        }
        if suggestions.arrangedSubviews.count != words.count || !(suggestions.arrangedSubviews.first is UIButton) {
            clear(suggestions)
            for index in words.indices {
                let button = makeSuggestionButton(""); button.titleLabel?.font = .systemFont(ofSize: 16)
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
        if pendingInput.deferIfBusy(.suggestion(word, prefix)) { return }
        // Recheck host context: a selection or cursor move invalidates the candidate.
        guard pendingPrefix == prefix,
              let context = SuggestionAcceptanceContext.precedingContext(
                prefix: prefix, documentContext: textDocumentProxy.documentContextBeforeInput),
              (textDocumentProxy.selectedText ?? "").isEmpty else { updateContext(); return }
        correctionUndo = nil; suppressedCorrection = nil
        completedWord = nil; lastSpace = nil; deletionUndo = nil; glideWords = []; glideUndo = nil
        for _ in prefix { textDocumentProxy.deleteBackward() }
        synchronizeCapitalization()
        let text = state.insertedWord(word) + " "
        textDocumentProxy.insertText(text)
        learnWord(word, after: String(context.dropLast(prefix.count)), language: state.language)
        completedWord = CompletedWordInsertion(origin: .suggestion, insertedText: text, context: inputContext)
        updateContext()
    }
    @objc private func alternatePress(_ gesture: UILongPressGestureRecognizer) {
        guard let button = gesture.view as? UIButton else { return }
        switch gesture.state {
        case .began:
            hideKeyPreview(); stopDeleting()
            let base = button.title(for: .normal)?.lowercased() ?? ""
            let alternatives = state.symbols ? state.symbolPage.holdAlternatives(for: base) : state.language.holdAlternatives(for: base, symbolsEnabled: settings.extraSymbols)
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
    deinit {
        previewHide?.cancel(); settingsHintTask?.cancel(); trailTimer?.invalidate()
    }
}
