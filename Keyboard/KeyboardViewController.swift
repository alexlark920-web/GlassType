import UIKit
import KeyboardCore

private final class DeleteKeyButton: UIButton {
    var deleteAction: (() -> Void)?
    override func accessibilityActivate() -> Bool {
        guard let deleteAction else { return false }
        deleteAction()
        return true
    }
}

final class KeyboardViewController: UIInputViewController {
    private var state = InputState()
    private let theme = KeyboardTheme.material
    private var settings = KeyboardSettings()
    private let provider: any SuggestionProvider = LocalSuggestionProvider()
    private let rows = UIStackView()
    private let suggestions = UIStackView()
    private let backdrop = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private var heightConstraint: NSLayoutConstraint?
    private var deleteTimer: Timer?
    private var deleteDelay: Timer?
    private var popup: UIView?
    private var popupValues: [String] = []
    private var popupLabels: [UILabel] = []
    private var popupIndex = 0
    private var letterButtons: [(UIButton, String)] = []
    private weak var shiftButton: UIButton?
    private var lastWidth: CGFloat = 0
    private var lastLandscape = false
    private var pendingPrefix: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        rows.translatesAutoresizingMaskIntoConstraints = false
        rows.axis = .vertical; rows.spacing = 7
        suggestions.heightAnchor.constraint(equalToConstant: 32).isActive = true
        view.addSubview(backdrop); view.addSubview(rows)
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor), backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: view.topAnchor), backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            rows.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 4),
            rows.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -4),
            rows.topAnchor.constraint(equalTo: view.topAnchor, constant: 5),
            rows.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -5)
        ])
        let height = view.heightAnchor.constraint(equalToConstant: 280)
        height.priority = .init(999); height.isActive = true; heightConstraint = height
        reloadSettings()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated); reloadSettings(); updateContext()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated); stopDeleting(); dismissPopup()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.width > 0 else { return }
        // A landscape keyboard can occupy a narrow split-screen host; use screen orientation too.
        let landscape = (view.window?.windowScene?.interfaceOrientation.isLandscape ?? false)
        let desired: CGFloat = (landscape ? 202 : 278) + view.safeAreaInsets.bottom
        if heightConstraint?.constant != desired { heightConstraint?.constant = desired }
        if abs(lastWidth - view.bounds.width) > 1 || landscape != lastLandscape {
            lastWidth = view.bounds.width; lastLandscape = landscape
            stopDeleting(); dismissPopup()
            for (button, _) in letterButtons { button.titleLabel?.font = .systemFont(ofSize: landscape ? 19 : 22) }
        }
    }
    override func textDidChange(_ textInput: UITextInput?) { updateContext() }
    override func selectionDidChange(_ textInput: UITextInput?) { dismissPopup(); updateContext() }
    private func reloadSettings() {
        settings = hasFullAccess ? KeyboardSettings.load() : KeyboardSettings()
        if !settings.languages.contains(state.language) { state.language = settings.languages.first ?? .english }
        switch settings.theme {
        case .system: overrideUserInterfaceStyle = .unspecified
        case .light: overrideUserInterfaceStyle = .light
        case .dark: overrideUserInterfaceStyle = .dark
        }
        rebuild()
    }
    private func clear(_ stack: UIStackView) {
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
    }
    private func rebuild() {
        stopDeleting(); dismissPopup(); clear(rows); clear(suggestions); letterButtons.removeAll(); shiftButton = nil
        suggestions.axis = .horizontal; suggestions.distribution = .fillEqually; suggestions.spacing = 6
        if settings.suggestions { rows.addArrangedSubview(suggestions) }
        let keyRows = state.symbols ? [Array("1234567890").map(String.init), ["@", "#", "$", "%", "&", "-", "+", "(", ")", "/"], ["*", "\"", "'", ":", ";", "!", "?"]] : state.language.rows
        for (index, keys) in keyRows.enumerated() {
            let row = UIStackView(); row.axis = .horizontal; row.distribution = .fillEqually; row.spacing = 4
            if index == 2 {
                let shift = makeButton(state.symbols ? "ABC" : "⇧", special: true)
                shift.accessibilityLabel = "Shift — двойное нажатие: Caps Lock"
                shift.addTarget(self, action: #selector(shiftTapped), for: .touchUpInside)
                shiftButton = shift; row.addArrangedSubview(shift)
            }
            for key in keys {
                let button = makeButton(key)
                button.accessibilityLabel = key
                button.addAction(UIAction { [weak self] _ in self?.insert(key) }, for: .touchUpInside)
                let alternatives = state.language.alternatives(for: key)
                if !alternatives.isEmpty {
                    let press = UILongPressGestureRecognizer(target: self, action: #selector(alternatePress(_:)))
                    press.minimumPressDuration = 0.38
                    button.addGestureRecognizer(press)
                    button.accessibilityHint = "Удерживайте для дополнительных символов"
                    button.accessibilityCustomActions = alternatives.map { value in
                        UIAccessibilityCustomAction(name: value) { [weak self] _ in self?.insert(value); return true }
                    }
                }
                letterButtons.append((button, key)); row.addArrangedSubview(button)
            }
            if index == 2 {
                let delete = makeButton("⌫", special: true); delete.accessibilityLabel = "Удалить"
                (delete as? DeleteKeyButton)?.deleteAction = { [weak self] in self?.deleteOnce() }
                delete.addTarget(self, action: #selector(startDeleting), for: .touchDown)
                delete.addTarget(self, action: #selector(stopDeleting), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
                delete.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Удалить символ") { [weak self] _ in self?.deleteOnce(); return true }]
                row.addArrangedSubview(delete)
            }
            rows.addArrangedSubview(row)
        }
        let bottom = UIStackView(); bottom.axis = .horizontal; bottom.spacing = 4
        let symbols = makeButton(state.symbols ? "ABC" : "?123", special: true)
        symbols.addAction(UIAction { [weak self] _ in guard let self else { return }; self.state.symbols.toggle(); self.rebuild() }, for: .touchUpInside)
        bottom.addArrangedSubview(symbols)
        if needsInputModeSwitchKey {
            let globe = makeButton("◎", special: true); globe.accessibilityLabel = "Следующая системная клавиатура"
            globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
            bottom.addArrangedSubview(globe)
        }
        let language = makeButton(state.language.rawValue.uppercased(), special: true)
        language.accessibilityLabel = "Сменить язык: \(state.language.title)"
        language.addAction(UIAction { [weak self] _ in guard let self else { return }; self.state.nextLanguage(enabled: self.settings.languages); self.rebuild() }, for: .touchUpInside)
        bottom.addArrangedSubview(language)
        let space = makeButton(state.language.title); space.accessibilityLabel = "Пробел"
        space.titleLabel?.font = .systemFont(ofSize: 14)
        space.addAction(UIAction { [weak self] _ in self?.insert(" ") }, for: .touchUpInside)
        bottom.addArrangedSubview(space)
        let punctuation = makeButton("."); punctuation.addAction(UIAction { [weak self] _ in self?.insert(".") }, for: .touchUpInside)
        let press = UILongPressGestureRecognizer(target: self, action: #selector(alternatePress(_:))); punctuation.addGestureRecognizer(press)
        bottom.addArrangedSubview(punctuation)
        let enter = makeButton(returnTitle(), special: true); enter.backgroundColor = .systemIndigo; enter.setTitleColor(.white, for: .normal)
        enter.accessibilityLabel = "Ввод"
        enter.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        enter.addAction(UIAction { [weak self] _ in self?.insert("\n") }, for: .touchUpInside)
        bottom.addArrangedSubview(enter)
        let unit = symbols.widthAnchor
        for item in bottom.arrangedSubviews where item !== space && item !== symbols {
            item.widthAnchor.constraint(equalTo: unit, multiplier: item === enter ? 1.35 : 0.85).isActive = true
        }
        space.widthAnchor.constraint(equalTo: unit, multiplier: 3.6).isActive = true
        rows.addArrangedSubview(bottom)
        // Four key rows share remaining height; the suggestion strip has fixed height.
        let keyViews = rows.arrangedSubviews.filter { $0 !== suggestions }
        for row in keyViews.dropFirst() { row.heightAnchor.constraint(equalTo: keyViews[0].heightAnchor).isActive = true }
        refreshLabels(); refreshSuggestions()
    }
    private func makeButton(_ title: String, special: Bool = false) -> UIButton {
        let button: UIButton = title == "⌫" ? DeleteKeyButton(type: .system) : UIButton(type: .system)
        button.setTitle(title, for: .normal); button.setTitleColor(theme.foreground, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: lastLandscape ? 19 : 22)
        button.titleLabel?.adjustsFontSizeToFitWidth = true; button.titleLabel?.minimumScaleFactor = 0.6
        button.backgroundColor = special ? theme.function : theme.key
        button.layer.cornerRadius = theme.radius; button.layer.cornerCurve = .continuous
        button.addAction(UIAction { [weak button] _ in button?.alpha = 0.55 }, for: .touchDown)
        button.addAction(UIAction { [weak button] _ in button?.alpha = 1 }, for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        return button
    }
    private func returnTitle() -> String {
        switch textDocumentProxy.returnKeyType ?? .default {
        case .go: return "Go"
        case .search: return "Поиск"
        case .send: return "Отпр."
        case .done: return "Готово"
        case .next: return "Далее"
        default: return "↵"
        }
    }
    private func insert(_ text: String) {
        textDocumentProxy.insertText(state.inserted(text)); updateContext()
    }
    @objc private func shiftTapped() {
        if state.symbols { state.symbols = false; rebuild(); return }
        state.tapShift(at: ProcessInfo.processInfo.systemUptime); refreshLabels()
    }
    private func refreshLabels() {
        for (button, key) in letterButtons {
            let value = state.shift == .off ? key : key.uppercased()
            button.setTitle(value, for: .normal); button.accessibilityLabel = value
        }
        if !state.symbols { shiftButton?.setTitle(state.shift == .locked ? "⇪" : "⇧", for: .normal) }
        shiftButton?.backgroundColor = state.shift == .off ? .tertiarySystemFill : .systemIndigo.withAlphaComponent(0.3)
        shiftButton?.accessibilityValue = state.shift == .locked ? "Caps Lock" : (state.shift == .once ? "Включён" : "Выключен")
    }
    @objc private func startDeleting() {
        stopDeleting(); deleteOnce()
        let delay = Timer(timeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self else { return }
            let repeatTimer = Timer(timeInterval: 0.075, repeats: true) { [weak self] _ in self?.deleteOnce() }
            self.deleteTimer = repeatTimer
            RunLoop.main.add(repeatTimer, forMode: .common)
        }
        deleteDelay = delay
        RunLoop.main.add(delay, forMode: .common)
    }
    @objc private func stopDeleting() { deleteDelay?.invalidate(); deleteDelay = nil; deleteTimer?.invalidate(); deleteTimer = nil }
    private func deleteOnce() { textDocumentProxy.deleteBackward(); updateContext() }
    private func updateContext() {
        let capitalization = textDocumentProxy.autocapitalizationType ?? .sentences
        state.synchronize(context: textDocumentProxy.documentContextBeforeInput, autoCapitalization: settings.autoCapitalization && capitalization != .none)
        refreshLabels(); refreshSuggestions()
    }
    private func refreshSuggestions() {
        clear(suggestions); pendingPrefix = nil
        guard settings.suggestions, let context = textDocumentProxy.documentContextBeforeInput else { return }
        let prefix = LocalSuggestionProvider.trailingWord(in: String(context.suffix(64)))
        guard !prefix.isEmpty, prefix.count < 64 else { return }
        pendingPrefix = prefix
        for candidate in provider.suggestions(context: context, language: state.language) {
            let word = prefix.first?.isUppercase == true ? (prefix.allSatisfy(\.isUppercase) && prefix.count > 1 ? candidate.uppercased() : candidate.capitalized) : candidate
            let button = makeButton(word); button.titleLabel?.font = .systemFont(ofSize: 16)
            button.addAction(UIAction { [weak self] _ in self?.accept(word, prefix: prefix) }, for: .touchUpInside)
            suggestions.addArrangedSubview(button)
        }
    }
    private func accept(_ word: String, prefix: String) {
        // Recheck host context: a selection or cursor move invalidates the candidate.
        guard pendingPrefix == prefix, let context = textDocumentProxy.documentContextBeforeInput,
              LocalSuggestionProvider.trailingWord(in: context) == prefix,
              textDocumentProxy.selectedText == nil else { updateContext(); return }
        for _ in prefix { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(word + " "); updateContext()
    }
    @objc private func alternatePress(_ gesture: UILongPressGestureRecognizer) {
        guard let button = gesture.view as? UIButton else { return }
        switch gesture.state {
        case .began:
            stopDeleting()
            let base = button.title(for: .normal)?.lowercased() ?? ""
            let values = [base] + state.language.alternatives(for: base)
            guard values.count > 1 else { return }
            popupValues = values; popupIndex = 0
            let panel = UIView(); panel.backgroundColor = .secondarySystemBackground
            panel.layer.cornerRadius = 12; panel.layer.borderWidth = 1; panel.layer.borderColor = UIColor.separator.cgColor
            let width = min(CGFloat(values.count) * 40, view.bounds.width - 8)
            let rect = button.convert(button.bounds, to: view)
            panel.frame = CGRect(x: min(max(4, rect.midX - width / 2), view.bounds.width - width - 4), y: max(2, rect.minY - 48), width: width, height: 44)
            for (index, value) in values.enumerated() {
                let label = UILabel(frame: CGRect(x: CGFloat(index) * width / CGFloat(values.count), y: 0, width: width / CGFloat(values.count), height: 44))
                label.textAlignment = .center; label.text = state.shift == .off ? value : value.uppercased(); label.font = .systemFont(ofSize: 23)
                panel.addSubview(label); popupLabels.append(label)
            }
            view.addSubview(panel); popup = panel; highlightPopup()
        case .changed:
            guard let panel = popup else { return }
            let point = gesture.location(in: panel)
            popupIndex = min(max(0, Int(point.x / (panel.bounds.width / CGFloat(popupValues.count)))), popupValues.count - 1)
            highlightPopup()
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
    deinit { deleteDelay?.invalidate(); deleteTimer?.invalidate() }
}
