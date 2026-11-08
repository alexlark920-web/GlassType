import Foundation

/// Cross-process repository for individually learned words. Context and typed
/// text are never stored; the in-memory cache contains only ranked words.
public final class PersonalLexiconRepository: @unchecked Sendable {
    public static let maximumWordCount = 5_000
    public static let learnedWordsNotificationName = "com.glasstype.shared.learned-words-updated"

    private let database: SharedDatabase
    private let cacheLimit: Int
    private let lock = NSLock()
    private var topWordCache: [String] = []
    private var cacheIsValid = false
    private var cacheGeneration: UInt64 = 0
    private var notificationObserver: DarwinNotificationObserver?

    public convenience init() throws {
        try self.init(database: SharedDatabase())
    }

    public init(database: SharedDatabase, cacheLimit: Int = 256) {
        self.database = database
        self.cacheLimit = min(max(1, cacheLimit), Self.maximumWordCount)
        notificationObserver = DarwinNotificationCenter.observe(name: Self.learnedWordsNotificationName) { [weak self] in
            self?.invalidateCache()
        }
    }

    public func learn(_ word: String, at date: Date = Date()) throws {
        try database.recordLearnedWord(word, at: date)
        lock.lock()
        cacheGeneration &+= 1
        cacheIsValid = false
        lock.unlock()
        DarwinNotificationCenter.post(name: Self.learnedWordsNotificationName)
    }

    public func topWords(limit: Int = 128) throws -> [String] {
        guard limit > 0 else { return [] }
        lock.lock()
        if cacheIsValid, limit <= topWordCache.count {
            let cached = Array(topWordCache.prefix(limit))
            lock.unlock()
            return cached
        }
        let generation = cacheGeneration
        lock.unlock()

        let words = try database.learnedWords(limit: max(limit, cacheLimit))
        lock.lock()
        let isCurrent = generation == cacheGeneration
        if isCurrent {
            topWordCache = words
            cacheIsValid = true
        }
        let result = Array(topWordCache.prefix(limit))
        lock.unlock()
        return isCurrent ? result : Array(words.prefix(limit))
    }

    public func count() throws -> Int { try database.learnedWordCount() }

    public func invalidateCache() {
        lock.lock(); cacheGeneration &+= 1; cacheIsValid = false; topWordCache.removeAll(keepingCapacity: true); lock.unlock()
    }
}
