import Foundation
import KeyboardCore

enum ThemeChoice: String, CaseIterable { case system, light, dark }
struct KeyboardSettings {
    // Must match both entitlements after changing the bundle identifier prefix.
    static let group = "group.org.opentype.GlassType"
    var theme: ThemeChoice = .system
    var suggestions = true
    var autoCapitalization = true
    var languages = KeyboardLanguage.allCases
    static func load(shared: Bool = true) -> KeyboardSettings {
        let defaults = shared ? (UserDefaults(suiteName: group) ?? .standard) : .standard
        var result = KeyboardSettings()
        result.theme = ThemeChoice(rawValue: defaults.string(forKey: "theme") ?? "") ?? .system
        result.suggestions = defaults.object(forKey: "suggestions") as? Bool ?? true
        result.autoCapitalization = defaults.object(forKey: "capitalization") as? Bool ?? true
        if let values = defaults.stringArray(forKey: "languages") {
            let languages = values.compactMap(KeyboardLanguage.init(rawValue:))
            if !languages.isEmpty { result.languages = languages }
        }
        return result
    }
    func save() {
        let defaults = UserDefaults(suiteName: Self.group) ?? .standard
        defaults.set(theme.rawValue, forKey: "theme")
        defaults.set(suggestions, forKey: "suggestions")
        defaults.set(autoCapitalization, forKey: "capitalization")
        defaults.set(languages.map(\.rawValue), forKey: "languages")
    }
}
