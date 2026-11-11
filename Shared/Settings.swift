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
    var usesSharedSettingsStorage = false
    var theme: ThemeChoice = .system
    var suggestions = true
    var autoCapitalization = true
    var languages = KeyboardLanguage.allCases
    var haptics: HapticChoice = .off
    var autoCorrection = true
    var compactKeys = true
    var showNumberRow = false
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
    var nextWordPrediction = true
    var personalizationEnabled = true
    var telemetryEnabled = false
    var keyboardHeightScale = 1.0
    var visualKeyWidthScale = 1.0
    var glideTrailFadeDuration = 0.28
    var glideTrailWidth = 4.5

    static func load(shared: Bool = true) -> KeyboardSettings {
        let defaults = shared ? (UserDefaults(suiteName: group) ?? .standard) : .standard
        var result = KeyboardSettings()
        result.theme = ThemeChoice(rawValue: defaults.string(forKey: "theme") ?? "") ?? .system
        result.suggestions = defaults.object(forKey: "suggestions") as? Bool ?? true
        result.autoCapitalization = defaults.object(forKey: "capitalization") as? Bool ?? true
        result.autoCorrection = defaults.object(forKey: "autoCorrection") as? Bool ?? true
        result.compactKeys = defaults.object(forKey: "compactKeys") as? Bool ?? true
        result.showNumberRow = defaults.object(forKey: "showNumberRow") as? Bool ?? false
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
        result.nextWordPrediction = defaults.object(forKey: "nextWordPrediction") as? Bool ?? true
        result.personalizationEnabled = defaults.object(forKey: "personalizationEnabled") as? Bool ?? true
        result.telemetryEnabled = defaults.object(forKey: "telemetryEnabled") as? Bool ?? false
        result.keyboardHeightScale = clampedKeyboardHeight(defaults.object(forKey: "keyboardHeightScale") as? Double ?? 1)
        result.visualKeyWidthScale = clampedVisualKeyWidth(defaults.object(forKey: "visualKeyWidthScale") as? Double ?? 1)
        result.glideTrailFadeDuration = clampedGlideTrailFadeDuration(defaults.object(forKey: "glideTrailFadeDuration") as? Double ?? 0.28)
        result.glideTrailWidth = clampedGlideTrailWidth(defaults.object(forKey: "glideTrailWidth") as? Double ?? 4.5)
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
        defaults.set(showNumberRow, forKey: "showNumberRow")
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
        defaults.set(nextWordPrediction, forKey: "nextWordPrediction")
        defaults.set(personalizationEnabled, forKey: "personalizationEnabled")
        defaults.set(telemetryEnabled, forKey: "telemetryEnabled")
        defaults.set(Self.clampedKeyboardHeight(keyboardHeightScale), forKey: "keyboardHeightScale")
        defaults.set(Self.clampedVisualKeyWidth(visualKeyWidthScale), forKey: "visualKeyWidthScale")
        defaults.set(Self.clampedGlideTrailFadeDuration(glideTrailFadeDuration), forKey: "glideTrailFadeDuration")
        defaults.set(Self.clampedGlideTrailWidth(glideTrailWidth), forKey: "glideTrailWidth")
        DarwinNotificationCenter.post(name: DarwinNotificationCenter.settingsUpdatedName)
    }
    private static let overrideKeys = ["keyboard.haptics", "keyboard.extraSymbols", "keyboard.symbolHints", "keyboard.holdDelay", "keyboard.autoCorrection", "keyboard.compactKeys", "keyboard.showKeyPreview", "keyboard.doubleSpacePeriod", "keyboard.swipeDeleteWord", "keyboard.glideTyping", "keyboard.personalLexicon", "keyboard.autoCapitalization", "keyboard.touchAdaptationEnabled", "keyboard.debugTouchZones", "keyboard.languages", "keyboard.interfaceLanguage", "keyboard.emojiKeyEnabled", "keyboard.allowProfanitySuggestions", "keyboard.nextWordPrediction", "keyboard.personalizationEnabled", "keyboard.keyboardHeightScale", "keyboard.visualKeyWidthScale", "keyboard.glideTrailFadeDuration", "keyboard.glideTrailWidth", "keyboard.showNumberRow"]
    /// Extension-local overrides make these controls usable with SideStore even
    /// when the re-signed app cannot share an App Group with its extension.
    static func loadKeyboard(fullAccess: Bool) -> KeyboardSettings {
        var result = fullAccess ? load() : KeyboardSettings()
        result.usesSharedSettingsStorage = fullAccess
        guard !fullAccess else { return result }
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
        if let value = defaults.object(forKey: overrideKeys[18]) as? Bool { result.nextWordPrediction = value }
        if let value = defaults.object(forKey: overrideKeys[19]) as? Bool { result.personalizationEnabled = value }
        if let value = defaults.object(forKey: overrideKeys[20]) as? Double { result.keyboardHeightScale = clampedKeyboardHeight(value) }
        if let value = defaults.object(forKey: overrideKeys[21]) as? Double { result.visualKeyWidthScale = clampedVisualKeyWidth(value) }
        if let value = defaults.object(forKey: overrideKeys[22]) as? Double { result.glideTrailFadeDuration = clampedGlideTrailFadeDuration(value) }
        if let value = defaults.object(forKey: overrideKeys[23]) as? Double { result.glideTrailWidth = clampedGlideTrailWidth(value) }
        if let value = defaults.object(forKey: overrideKeys[24]) as? Bool { result.showNumberRow = value }
        return result
    }
    func saveKeyboardOverrides() {
        if usesSharedSettingsStorage {
            save()
            return
        }
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
        defaults.set(nextWordPrediction, forKey: Self.overrideKeys[18])
        defaults.set(personalizationEnabled, forKey: Self.overrideKeys[19])
        defaults.set(Self.clampedKeyboardHeight(keyboardHeightScale), forKey: Self.overrideKeys[20])
        defaults.set(Self.clampedVisualKeyWidth(visualKeyWidthScale), forKey: Self.overrideKeys[21])
        defaults.set(Self.clampedGlideTrailFadeDuration(glideTrailFadeDuration), forKey: Self.overrideKeys[22])
        defaults.set(Self.clampedGlideTrailWidth(glideTrailWidth), forKey: Self.overrideKeys[23])
        defaults.set(showNumberRow, forKey: Self.overrideKeys[24])
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
    static func clampedKeyboardHeight(_ value: Double) -> Double {
        KeyboardSizing.heightScale(value)
    }
    static func clampedVisualKeyWidth(_ value: Double) -> Double {
        KeyboardSizing.visualWidthScale(value)
    }
    static func clampedGlideTrailFadeDuration(_ value: Double) -> Double {
        value.isFinite ? min(0.8, max(0.1, value)) : 0.28
    }
    static func clampedGlideTrailWidth(_ value: Double) -> Double {
        value.isFinite ? min(10, max(2, value)) : 4.5
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

struct TouchTelemetrySummary: Codable {
    let portraitSamples: Int
    let portraitMeanOffsetX: Double
    let portraitMeanOffsetY: Double
    let portraitSigmaX: Double
    let portraitSigmaY: Double
    let landscapeSamples: Int
    let landscapeMeanOffsetX: Double
    let landscapeMeanOffsetY: Double
    let landscapeSigmaX: Double
    let landscapeSigmaY: Double

    init(_ state: TouchAdaptationState) {
        portraitSamples = state.portrait.count
        portraitMeanOffsetX = state.portrait.meanX
        portraitMeanOffsetY = state.portrait.meanY
        portraitSigmaX = state.portrait.learnedSigmaX
        portraitSigmaY = state.portrait.learnedSigmaY
        landscapeSamples = state.landscape.count
        landscapeMeanOffsetX = state.landscape.meanX
        landscapeMeanOffsetY = state.landscape.meanY
        landscapeSigmaX = state.landscape.learnedSigmaX
        landscapeSigmaY = state.landscape.learnedSigmaY
    }
}

struct KeyboardTelemetrySnapshot: Codable {
    var textKeysCommitted = 0
    var suggestionSetsShown = 0
    var suggestionCandidatesShown = 0
    var suggestionAcceptancesByRank = [0, 0, 0]
    var nextWordSuggestionSetsShown = 0
    var nextWordAcceptancesByRank = [0, 0, 0]
    var autocorrectionsApplied = 0
    var autocorrectionsUndone = 0
    var glideAttempts = 0
    var glideWordsInserted = 0
    var glideAlternativesAcceptedByRank = [0, 0, 0]
    var dictionaryWordsAdded = 0
    var predictionLatencyUnder5ms = 0
    var predictionLatencyUnder15ms = 0
    var predictionLatencyUnder50ms = 0
    var predictionLatencyAtLeast50ms = 0
    var touchAdaptation: TouchTelemetrySummary? = nil

    private enum CodingKeys: String, CodingKey {
        case textKeysCommitted, suggestionSetsShown, suggestionCandidatesShown, suggestionAcceptancesByRank
        case nextWordSuggestionSetsShown, nextWordAcceptancesByRank, autocorrectionsApplied, autocorrectionsUndone
        case glideAttempts, glideWordsInserted, glideAlternativesAcceptedByRank, dictionaryWordsAdded
        case predictionLatencyUnder5ms, predictionLatencyUnder15ms, predictionLatencyUnder50ms
        case predictionLatencyAtLeast50ms, touchAdaptation
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func count(_ key: CodingKeys) throws -> Int {
            max(0, try container.decodeIfPresent(Int.self, forKey: key) ?? 0)
        }
        func ranks(_ key: CodingKeys) throws -> [Int] {
            let values = try container.decodeIfPresent([Int].self, forKey: key) ?? []
            return (0..<3).map { values.indices.contains($0) ? max(0, values[$0]) : 0 }
        }
        textKeysCommitted = try count(.textKeysCommitted)
        suggestionSetsShown = try count(.suggestionSetsShown)
        suggestionCandidatesShown = try count(.suggestionCandidatesShown)
        suggestionAcceptancesByRank = try ranks(.suggestionAcceptancesByRank)
        nextWordSuggestionSetsShown = try count(.nextWordSuggestionSetsShown)
        nextWordAcceptancesByRank = try ranks(.nextWordAcceptancesByRank)
        autocorrectionsApplied = try count(.autocorrectionsApplied)
        autocorrectionsUndone = try count(.autocorrectionsUndone)
        glideAttempts = try count(.glideAttempts)
        glideWordsInserted = try count(.glideWordsInserted)
        glideAlternativesAcceptedByRank = try ranks(.glideAlternativesAcceptedByRank)
        dictionaryWordsAdded = try count(.dictionaryWordsAdded)
        predictionLatencyUnder5ms = try count(.predictionLatencyUnder5ms)
        predictionLatencyUnder15ms = try count(.predictionLatencyUnder15ms)
        predictionLatencyUnder50ms = try count(.predictionLatencyUnder50ms)
        predictionLatencyAtLeast50ms = try count(.predictionLatencyAtLeast50ms)
        touchAdaptation = try container.decodeIfPresent(TouchTelemetrySummary.self, forKey: .touchAdaptation)
    }
}

struct KeyboardTelemetryExport: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let appVersion: String?
    let buildNumber: String?
    let operatingSystemVersion: String
    let statistics: KeyboardTelemetrySnapshot

    init(snapshot: KeyboardTelemetrySnapshot, appVersion: String?, buildNumber: String?,
         operatingSystemVersion: String) {
        schemaVersion = 1
        exportedAt = Date()
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.operatingSystemVersion = operatingSystemVersion
        statistics = snapshot
    }
}

enum KeyboardTelemetryStorageError: Error {
    case sharedContainerUnavailable
    case resetWhileWriting
}

enum KeyboardTelemetryStorage {
    private static let dataKey = "keyboard.telemetry.v1"
    private static let epochKey = "keyboard.telemetry.epoch"

    private static func sharedDefaults() throws -> UserDefaults {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: KeyboardSettings.group) != nil,
              let defaults = UserDefaults(suiteName: KeyboardSettings.group) else {
            throw KeyboardTelemetryStorageError.sharedContainerUnavailable
        }
        return defaults
    }

    static func read() throws -> (epoch: String, snapshot: KeyboardTelemetrySnapshot?) {
        let defaults = try sharedDefaults()
        let epoch = defaults.string(forKey: epochKey) ?? "initial"
        guard let data = defaults.data(forKey: dataKey) else { return (epoch, nil) }
        return (epoch, try JSONDecoder().decode(KeyboardTelemetrySnapshot.self, from: data))
    }

    static func write(_ snapshot: KeyboardTelemetrySnapshot, expectedEpoch: String) throws {
        let defaults = try sharedDefaults()
        guard (defaults.string(forKey: epochKey) ?? "initial") == expectedEpoch else {
            throw KeyboardTelemetryStorageError.resetWhileWriting
        }
        defaults.set(try JSONEncoder().encode(snapshot), forKey: dataKey)
    }

    static func reset() throws {
        let defaults = try sharedDefaults()
        defaults.removeObject(forKey: dataKey)
        defaults.set(UUID().uuidString, forKey: epochKey)
        DarwinNotificationCenter.post(name: DarwinNotificationCenter.settingsUpdatedName)
    }
}

struct KeyboardTelemetryRecorder {
    private var enabled = false
    private var epoch: String?
    private var snapshot: KeyboardTelemetrySnapshot?
    private var hasPendingChanges = false

    mutating func configure(enabled: Bool) {
        if self.enabled && !enabled { flush() }
        self.enabled = enabled
        guard enabled else { return }
        synchronize()
    }

    mutating func recordTextKeyCommit() { update { $0.textKeysCommitted += 1 } }

    mutating func recordSuggestionSet(candidateCount: Int, nextWord: Bool) {
        update {
            $0.suggestionSetsShown += 1
            $0.suggestionCandidatesShown += max(0, candidateCount)
            if nextWord { $0.nextWordSuggestionSetsShown += 1 }
        }
    }

    mutating func recordSuggestionAccepted(rank: Int, nextWord: Bool) {
        update {
            guard (0..<3).contains(rank) else { return }
            if nextWord { $0.nextWordAcceptancesByRank[rank] += 1 }
            else { $0.suggestionAcceptancesByRank[rank] += 1 }
        }
    }

    mutating func recordAutocorrectionApplied() { update { $0.autocorrectionsApplied += 1 } }
    mutating func recordAutocorrectionUndone() { update { $0.autocorrectionsUndone += 1 } }
    mutating func recordGlideAttempt() { update { $0.glideAttempts += 1 } }
    mutating func recordGlideWordInserted() { update { $0.glideWordsInserted += 1 } }

    mutating func recordGlideAlternativeAccepted(rank: Int) {
        update {
            guard (0..<3).contains(rank) else { return }
            $0.glideAlternativesAcceptedByRank[rank] += 1
        }
    }

    mutating func recordDictionaryWordAdded() { update { $0.dictionaryWordsAdded += 1 } }

    mutating func recordPredictionLatency(milliseconds: Double) {
        guard milliseconds.isFinite, milliseconds >= 0 else { return }
        update {
            if milliseconds < 5 { $0.predictionLatencyUnder5ms += 1 }
            else if milliseconds < 15 { $0.predictionLatencyUnder15ms += 1 }
            else if milliseconds < 50 { $0.predictionLatencyUnder50ms += 1 }
            else { $0.predictionLatencyAtLeast50ms += 1 }
        }
    }

    mutating func recordTouchAdaptation(_ state: TouchAdaptationState) {
        update { $0.touchAdaptation = TouchTelemetrySummary(state) }
    }

    mutating func flush() {
        guard enabled, hasPendingChanges, var snapshot, let epoch else { return }
        do {
            try KeyboardTelemetryStorage.write(snapshot, expectedEpoch: epoch)
            self.snapshot = snapshot
            hasPendingChanges = false
        } catch KeyboardTelemetryStorageError.resetWhileWriting {
            synchronize()
        } catch {
            NSLog("GlassType telemetry could not be saved: %@", String(describing: error))
            enabled = false
        }
    }

    private mutating func update(_ change: (inout KeyboardTelemetrySnapshot) -> Void) {
        guard enabled else { return }
        if snapshot == nil { synchronize() }
        guard var snapshot else { return }
        change(&snapshot)
        self.snapshot = snapshot
        hasPendingChanges = true
    }

    private mutating func synchronize() {
        do {
            let stored = try KeyboardTelemetryStorage.read()
            if epoch != stored.epoch {
                epoch = stored.epoch
                snapshot = stored.snapshot ?? KeyboardTelemetrySnapshot()
                hasPendingChanges = false
            } else if snapshot == nil {
                snapshot = stored.snapshot ?? KeyboardTelemetrySnapshot()
            }
        } catch {
            NSLog("GlassType telemetry could not be loaded: %@", String(describing: error))
            enabled = false
            epoch = nil
            snapshot = nil
            hasPendingChanges = false
        }
    }
}
