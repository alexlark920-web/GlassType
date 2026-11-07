import Foundation
import KeyboardCore

enum ThemeChoice: String, CaseIterable { case system, light, dark }
enum HapticChoice: String, CaseIterable {
    case off, light, medium, strong
    var title: String {
        switch self {
        case .off: return "Нет"
        case .light: return "Слаб."
        case .medium: return "Сред."
        case .strong: return "Сильно"
        }
    }
}
struct KeyboardSettings {
    // Must match both entitlements after changing the bundle identifier prefix.
    static let group = "group.org.opentype.GlassType"
    var theme: ThemeChoice = .system
    var suggestions = true
    var autoCapitalization = true
    var languages = KeyboardLanguage.allCases
    var haptics: HapticChoice = .off
    var autoCorrection = true
    var compactKeys = true
    var showKeyPreview = true
    var doubleSpacePeriod = true
    var swipeDeleteWord = true
    var glideTyping = true
    var touchAdaptationEnabled = false
    var debugTouchZones = false
    var personalLexicon = PersonalLexicon()
    var extraSymbols = true
    var symbolHints = true
    var holdDelay: Double = 0.4
    var interfaceLanguage: InterfaceLanguage = .russian
    var emojiKeyEnabled = false
    var allowProfanitySuggestions = false

    static func load(shared: Bool = true) -> KeyboardSettings {
        let defaults = shared ? (UserDefaults(suiteName: group) ?? .standard) : .standard
        var result = KeyboardSettings()
        result.theme = ThemeChoice(rawValue: defaults.string(forKey: "theme") ?? "") ?? .system
        result.suggestions = defaults.object(forKey: "suggestions") as? Bool ?? true
        result.autoCapitalization = defaults.object(forKey: "capitalization") as? Bool ?? true
        result.autoCorrection = defaults.object(forKey: "autoCorrection") as? Bool ?? true
        result.compactKeys = defaults.object(forKey: "compactKeys") as? Bool ?? true
        result.showKeyPreview = defaults.object(forKey: "showKeyPreview") as? Bool ?? true
        result.doubleSpacePeriod = defaults.object(forKey: "doubleSpacePeriod") as? Bool ?? true
        result.swipeDeleteWord = defaults.object(forKey: "swipeDeleteWord") as? Bool ?? true
        result.glideTyping = defaults.object(forKey: "glideTyping") as? Bool ?? true
        result.touchAdaptationEnabled = defaults.object(forKey: "touchAdaptationEnabled") as? Bool ?? false
        result.debugTouchZones = defaults.object(forKey: "debugTouchZones") as? Bool ?? false
        if let data = defaults.data(forKey: "personalLexicon"), let lexicon = try? JSONDecoder().decode(PersonalLexicon.self, from: data) { result.personalLexicon = lexicon.sanitized() }
        result.haptics = HapticChoice(rawValue: defaults.string(forKey: "haptics") ?? "") ?? .off
        result.extraSymbols = defaults.object(forKey: "extraSymbols") as? Bool ?? true
        result.symbolHints = defaults.object(forKey: "symbolHints") as? Bool ?? true
        result.holdDelay = clampedDelay(defaults.object(forKey: "holdDelay") as? Double ?? 0.4)
        result.interfaceLanguage = InterfaceLanguage(rawValue: defaults.string(forKey: "interfaceLanguage") ?? "") ?? .russian
        result.emojiKeyEnabled = defaults.object(forKey: "emojiKeyEnabled") as? Bool ?? false
        result.allowProfanitySuggestions = defaults.object(forKey: "allowProfanitySuggestions") as? Bool ?? false
        if let values = defaults.stringArray(forKey: "languages") {
            result.languages = EnabledKeyboardLanguages.normalized(values.compactMap(KeyboardLanguage.init(rawValue:)))
        }
        return result
    }
    func save() {
        let defaults = UserDefaults(suiteName: Self.group) ?? .standard
        defaults.set(theme.rawValue, forKey: "theme")
        defaults.set(suggestions, forKey: "suggestions")
        defaults.set(autoCapitalization, forKey: "capitalization")
        defaults.set(EnabledKeyboardLanguages.normalized(languages).map(\.rawValue), forKey: "languages")
        defaults.set(autoCorrection, forKey: "autoCorrection")
        defaults.set(compactKeys, forKey: "compactKeys")
        defaults.set(showKeyPreview, forKey: "showKeyPreview")
        defaults.set(doubleSpacePeriod, forKey: "doubleSpacePeriod")
        defaults.set(swipeDeleteWord, forKey: "swipeDeleteWord")
        defaults.set(glideTyping, forKey: "glideTyping")
        defaults.set(touchAdaptationEnabled, forKey: "touchAdaptationEnabled")
        defaults.set(debugTouchZones, forKey: "debugTouchZones")
        defaults.set(try? JSONEncoder().encode(personalLexicon.sanitized()), forKey: "personalLexicon")
        defaults.set(haptics.rawValue, forKey: "haptics")
        defaults.set(extraSymbols, forKey: "extraSymbols")
        defaults.set(symbolHints, forKey: "symbolHints")
        defaults.set(Self.clampedDelay(holdDelay), forKey: "holdDelay")
        defaults.set(interfaceLanguage.rawValue, forKey: "interfaceLanguage")
        defaults.set(emojiKeyEnabled, forKey: "emojiKeyEnabled")
        defaults.set(allowProfanitySuggestions, forKey: "allowProfanitySuggestions")
    }
    private static let overrideKeys = ["keyboard.haptics", "keyboard.extraSymbols", "keyboard.symbolHints", "keyboard.holdDelay", "keyboard.autoCorrection", "keyboard.compactKeys", "keyboard.showKeyPreview", "keyboard.doubleSpacePeriod", "keyboard.swipeDeleteWord", "keyboard.glideTyping", "keyboard.personalLexicon", "keyboard.autoCapitalization", "keyboard.touchAdaptationEnabled", "keyboard.debugTouchZones", "keyboard.languages", "keyboard.interfaceLanguage", "keyboard.emojiKeyEnabled", "keyboard.allowProfanitySuggestions"]
    /// Extension-local overrides make these controls usable with SideStore even
    /// when the re-signed app cannot share an App Group with its extension.
    static func loadKeyboard(fullAccess: Bool) -> KeyboardSettings {
        var result = fullAccess ? load() : KeyboardSettings()
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: overrideKeys[0]), let value = HapticChoice(rawValue: raw) { result.haptics = value }
        if let value = defaults.object(forKey: overrideKeys[1]) as? Bool { result.extraSymbols = value }
        if let value = defaults.object(forKey: overrideKeys[2]) as? Bool { result.symbolHints = value }
        if let value = defaults.object(forKey: overrideKeys[3]) as? Double { result.holdDelay = clampedDelay(value) }
        if let value = defaults.object(forKey: overrideKeys[4]) as? Bool { result.autoCorrection = value }
        if let value = defaults.object(forKey: overrideKeys[5]) as? Bool { result.compactKeys = value }
        if let value = defaults.object(forKey: overrideKeys[6]) as? Bool { result.showKeyPreview = value }
        if let v = defaults.object(forKey: overrideKeys[7]) as? Bool { result.doubleSpacePeriod = v }
        if let v = defaults.object(forKey: overrideKeys[8]) as? Bool { result.swipeDeleteWord = v }
        if let v = defaults.object(forKey: overrideKeys[9]) as? Bool { result.glideTyping = v }
        if let data = defaults.data(forKey: overrideKeys[10]), let lexicon = try? JSONDecoder().decode(PersonalLexicon.self, from: data) { result.personalLexicon = lexicon.sanitized() }
        if let v = defaults.object(forKey: overrideKeys[11]) as? Bool { result.autoCapitalization = v }
        if let v = defaults.object(forKey: overrideKeys[12]) as? Bool { result.touchAdaptationEnabled = v }
        if let v = defaults.object(forKey: overrideKeys[13]) as? Bool { result.debugTouchZones = v }
        if let values = defaults.stringArray(forKey: overrideKeys[14]) {
            result.languages = EnabledKeyboardLanguages.normalized(values.compactMap(KeyboardLanguage.init(rawValue:)))
        }
        if let raw = defaults.string(forKey: overrideKeys[15]), let value = InterfaceLanguage(rawValue: raw) { result.interfaceLanguage = value }
        if let value = defaults.object(forKey: overrideKeys[16]) as? Bool { result.emojiKeyEnabled = value }
        if let value = defaults.object(forKey: overrideKeys[17]) as? Bool { result.allowProfanitySuggestions = value }
        return result
    }
    func saveKeyboardOverrides() {
        let defaults = UserDefaults.standard
        defaults.set(EnabledKeyboardLanguages.normalized(languages).map(\.rawValue), forKey: Self.overrideKeys[14])
        defaults.set(autoCapitalization, forKey: Self.overrideKeys[11])
        defaults.set(touchAdaptationEnabled, forKey: Self.overrideKeys[12])
        defaults.set(debugTouchZones, forKey: Self.overrideKeys[13])
        defaults.set(doubleSpacePeriod, forKey: Self.overrideKeys[7])
        defaults.set(swipeDeleteWord, forKey: Self.overrideKeys[8])
        defaults.set(glideTyping, forKey: Self.overrideKeys[9])
        defaults.set(try? JSONEncoder().encode(personalLexicon.sanitized()), forKey: Self.overrideKeys[10])
        defaults.set(autoCorrection, forKey: Self.overrideKeys[4])
        defaults.set(compactKeys, forKey: Self.overrideKeys[5])
        defaults.set(showKeyPreview, forKey: Self.overrideKeys[6])
        defaults.set(haptics.rawValue, forKey: Self.overrideKeys[0])
        defaults.set(extraSymbols, forKey: Self.overrideKeys[1])
        defaults.set(symbolHints, forKey: Self.overrideKeys[2])
        defaults.set(Self.clampedDelay(holdDelay), forKey: Self.overrideKeys[3])
        defaults.set(interfaceLanguage.rawValue, forKey: Self.overrideKeys[15])
        defaults.set(emojiKeyEnabled, forKey: Self.overrideKeys[16])
        defaults.set(allowProfanitySuggestions, forKey: Self.overrideKeys[17])
    }
    static func clearKeyboardOverrides() {
        for key in overrideKeys where key != "keyboard.personalLexicon" { UserDefaults.standard.removeObject(forKey: key) }
    }
    static func lastUsedLanguage(enabled: [KeyboardLanguage]) -> KeyboardLanguage {
        if let raw = UserDefaults.standard.string(forKey: "keyboard.lastLanguage"), let language = KeyboardLanguage(rawValue: raw), enabled.contains(language) { return language }
        return enabled.first ?? .english
    }
    static func rememberLanguage(_ language: KeyboardLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: "keyboard.lastLanguage")
    }
    private static func clampedDelay(_ value: Double) -> Double {
        value.isFinite ? min(0.8, max(0.25, value)) : 0.4
    }
}

/// Extension sandbox only, works without Full Access/App Groups/SideStore entitlements.
/// Writes are batched by the controller; no raw samples ever reach UserDefaults.
enum TouchCalibrationStorage {
    private static let key = "keyboard.touchCalibration.v1"
    static func load() -> TouchAdaptationState {
        guard let data = UserDefaults.standard.data(forKey: key), data.count <= 2048,
              let value = try? JSONDecoder().decode(TouchAdaptationState.self, from: data), value.isValid else { return .init() }
        return value
    }
    static func save(_ value: TouchAdaptationState) {
        guard value.isValid, let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
    static func reset() { UserDefaults.standard.removeObject(forKey: key) }
}
