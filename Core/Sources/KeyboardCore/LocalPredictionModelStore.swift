import Foundation

/// Extension-container persistence for the compact personal n-gram profile.
/// UserDefaults.standard is deliberately used so prediction works without
/// App Groups or Full Access. Only bounded aggregate counts are stored.
public final class LocalPredictionModelStore {
    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()
    private var cachedModel: PersonalNGramModel?
    private static let maximumEncodedBytes = 48 * 1024

    public init(defaults: UserDefaults = .standard,
                key: String = "keyboard.localPredictionProfile.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func snapshot() -> PersonalNGramModel {
        lock.lock(); defer { lock.unlock() }
        return loadLocked()
    }

    public func observe(context: String, nextWord: String, language: KeyboardLanguage) {
        lock.lock(); defer { lock.unlock() }
        var model = loadLocked()
        model.observe(context: context, nextWord: nextWord, language: language)
        model = model.sanitized()
        guard let data = try? JSONEncoder().encode(model), data.count <= Self.maximumEncodedBytes else { return }
        defaults.set(data, forKey: key)
        cachedModel = model
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        cachedModel = PersonalNGramModel()
        defaults.removeObject(forKey: key)
    }

    private func loadLocked() -> PersonalNGramModel {
        if let cachedModel { return cachedModel }
        let data = defaults.data(forKey: key)
        let decoded = data.flatMap { data -> PersonalNGramModel? in
            guard data.count <= Self.maximumEncodedBytes else { return nil }
            return try? JSONDecoder().decode(PersonalNGramModel.self, from: data)
        }
        let model = decoded?.sanitized() ?? PersonalNGramModel()
        cachedModel = model
        return model
    }
}
