import CSQLite
import Foundation

public enum SharedDatabaseError: Error, Sendable, Equatable {
    case appGroupUnavailable(String)
    case sqlite(code: Int32, message: String)
    case invalidWord
}

/// A small SQLite connection rooted in the shared App Group container.
/// Each instance serializes its own connection; SQLite WAL and busy timeout
/// coordinate separate connections in the app and keyboard extension.
public final class SharedDatabase: @unchecked Sendable {
    public static let appGroupIdentifier = "group.com.glasstype.shared"
    public static let fileName = "GlassTypeShared.sqlite"

    private let lock = NSLock()
    private var connection: OpaquePointer?
    public let fileURL: URL

    public convenience init(appGroupIdentifier: String = Self.appGroupIdentifier) throws {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw SharedDatabaseError.appGroupUnavailable(appGroupIdentifier)
        }
        try self.init(url: container.appendingPathComponent(Self.fileName))
    }

    /// Injectable file URL for tests and local development.
    public init(url: URL) throws {
        fileURL = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let openResult = sqlite3_open_v2(url.path, &connection, flags, nil)
        guard openResult == SQLITE_OK, let handle = connection else {
            let message = self.connection.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            if let handle = self.connection { sqlite3_close_v2(handle) }
            self.connection = nil
            throw SharedDatabaseError.sqlite(code: openResult, message: message)
        }
        sqlite3_busy_timeout(handle, 3_000)
        try executeRaw("PRAGMA journal_mode=WAL;")
        try executeRaw("PRAGMA busy_timeout=3000;")
        try executeRaw("""
            CREATE TABLE IF NOT EXISTS learned_words (
                word TEXT PRIMARY KEY NOT NULL,
                usage_count INTEGER NOT NULL DEFAULT 1,
                last_used REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS learned_words_rank ON learned_words(usage_count DESC, last_used DESC);
            CREATE TRIGGER IF NOT EXISTS learned_words_lru_insert AFTER INSERT ON learned_words BEGIN
                DELETE FROM learned_words WHERE word IN (
                    SELECT word FROM learned_words ORDER BY last_used DESC, word ASC LIMIT -1 OFFSET 5000
                );
            END;
            CREATE TRIGGER IF NOT EXISTS learned_words_lru_update AFTER UPDATE ON learned_words BEGIN
                DELETE FROM learned_words WHERE word IN (
                    SELECT word FROM learned_words ORDER BY last_used DESC, word ASC LIMIT -1 OFFSET 5000
                );
            END;
            """)
    }

    deinit {
        if let connection { sqlite3_close_v2(connection) }
    }

    public func recordLearnedWord(_ word: String, at date: Date = Date()) throws {
        let normalized = Self.normalize(word)
        guard (1...64).contains(normalized.count), normalized.allSatisfy({ $0.isLetter || "'’ʼ-".contains($0) }) else {
            throw SharedDatabaseError.invalidWord
        }
        try withLock {
            let statement = try prepare("""
                INSERT INTO learned_words(word, usage_count, last_used) VALUES(?, 1, ?)
                ON CONFLICT(word) DO UPDATE SET usage_count = usage_count + 1, last_used = excluded.last_used;
                """)
            defer { sqlite3_finalize(statement) }
            try bind([.text(normalized), .real(date.timeIntervalSince1970)], to: statement)
            try stepDone(statement)
        }
    }

    /// Returns the most frequently and recently used words, bounded by limit.
    public func learnedWords(limit: Int = 128) throws -> [String] {
        guard limit > 0 else { return [] }
        return try withLock {
            let statement = try prepare("SELECT word FROM learned_words ORDER BY usage_count DESC, last_used DESC, word ASC LIMIT ?;")
            defer { sqlite3_finalize(statement) }
            try bind([.integer(Int64(min(limit, 5_000)))], to: statement)
            var words: [String] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { break }
                guard result == SQLITE_ROW else { throw error(result) }
                if let text = sqlite3_column_text(statement, 0) { words.append(String(cString: text)) }
            }
            return words
        }
    }

    public func learnedWordCount() throws -> Int {
        try withLock {
            let statement = try prepare("SELECT COUNT(*) FROM learned_words;")
            defer { sqlite3_finalize(statement) }
            let result = sqlite3_step(statement)
            guard result == SQLITE_ROW else { throw error(result) }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    public func journalMode() throws -> String {
        try withLock {
            let statement = try prepare("PRAGMA journal_mode;")
            defer { sqlite3_finalize(statement) }
            let result = sqlite3_step(statement)
            guard result == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { throw error(result) }
            return String(cString: text)
        }
    }

    public func busyTimeoutMilliseconds() throws -> Int {
        try withLock {
            let statement = try prepare("PRAGMA busy_timeout;")
            defer { sqlite3_finalize(statement) }
            let result = sqlite3_step(statement)
            guard result == SQLITE_ROW else { throw error(result) }
            return Int(sqlite3_column_int(statement, 0))
        }
    }

    private enum Binding {
        case text(String)
        case integer(Int64)
        case real(Double)
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }

    private func executeRaw(_ sql: String) throws {
        try withLock {
            guard let connection else { throw SharedDatabaseError.sqlite(code: SQLITE_MISUSE, message: "Database is closed") }
            var message: UnsafeMutablePointer<CChar>?
            let result = sqlite3_exec(connection, sql, nil, nil, &message)
            guard result == SQLITE_OK else {
                let text = message.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(connection))
                sqlite3_free(message)
                throw SharedDatabaseError.sqlite(code: result, message: text)
            }
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let connection else { throw SharedDatabaseError.sqlite(code: SQLITE_MISUSE, message: "Database is closed") }
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else { throw error(result) }
        return statement
    }

    private func bind(_ values: [Binding], to statement: OpaquePointer) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let string):
                result = string.withCString { sqlite3_bind_text(statement, index, $0, -1, Self.sqliteTransient) }
            case .integer(let integer): result = sqlite3_bind_int64(statement, index, integer)
            case .real(let number): result = sqlite3_bind_double(statement, index, number)
            }
            guard result == SQLITE_OK else { throw error(result) }
        }
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else { throw error(result) }
    }

    private func error(_ code: Int32) -> SharedDatabaseError {
        SharedDatabaseError.sqlite(code: code, message: connection.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite error")
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func normalize(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping.lowercased()
    }
}
