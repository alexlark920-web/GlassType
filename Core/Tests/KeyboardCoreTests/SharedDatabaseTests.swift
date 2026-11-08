import Foundation
import XCTest
@testable import KeyboardCore

final class SharedDatabaseTests: XCTestCase {
    private func temporaryDatabaseURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GlassTypeDatabaseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(SharedDatabase.fileName)
    }

    private static func generatedWord(_ index: Int) -> String {
        var value = index
        var suffix = ""
        repeat {
            suffix = String(UnicodeScalar(97 + value % 26)!) + suffix
            value /= 26
        } while value > 0
        return "word" + suffix
    }

    func testDatabaseUsesWALAndSharesWordsAcrossConnections() throws {
        let url = try temporaryDatabaseURL()
        let host = try SharedDatabase(url: url)
        let keyboard = try SharedDatabase(url: url)

        XCTAssertEqual(try host.journalMode().lowercased(), "wal")
        XCTAssertEqual(try host.busyTimeoutMilliseconds(), 3_000)
        try host.recordLearnedWord("Привіт")
        XCTAssertEqual(try keyboard.learnedWords(), ["привіт"])
    }

    func testSimultaneousReadsAndWritesAcrossConnectionsDoNotLockOut() throws {
        let url = try temporaryDatabaseURL()
        let host = try SharedDatabase(url: url)
        let keyboard = try SharedDatabase(url: url)
        let failures = FailureCollector()

        DispatchQueue.concurrentPerform(iterations: 160) { index in
            let database = index.isMultiple(of: 2) ? host : keyboard
            do {
                try database.recordLearnedWord(Self.generatedWord(index % 24), at: Date(timeIntervalSince1970: Double(index)))
                _ = try database.learnedWords(limit: 32)
            } catch {
                failures.append(error)
            }
        }

        XCTAssertTrue(failures.errors.isEmpty, failures.errors.map { String(describing: $0) }.joined(separator: "\n"))
        XCTAssertEqual(try host.learnedWordCount(), 24)
    }

    func testLRUTriggerKeepsAtMostFiveThousandWords() throws {
        let database = try SharedDatabase(url: temporaryDatabaseURL())
        let firstUse = Date(timeIntervalSince1970: 1)
        for index in 0..<5_120 {
            try database.recordLearnedWord(Self.generatedWord(index), at: firstUse.addingTimeInterval(Double(index)))
        }
        XCTAssertEqual(try database.learnedWordCount(), PersonalLexiconRepository.maximumWordCount)
        XCTAssertFalse(try database.learnedWords(limit: 5_000).contains(Self.generatedWord(0)))
        XCTAssertTrue(try database.learnedWords(limit: 5_000).contains(Self.generatedWord(5_119)))
    }

    func testRepositoryCachesTopWordsAndRejectsInvalidEntries() throws {
        let repository = PersonalLexiconRepository(database: try SharedDatabase(url: temporaryDatabaseURL()), cacheLimit: 8)
        try repository.learn("keyboard")
        try repository.learn("keyboard")
        try repository.learn("swift")
        XCTAssertEqual(try repository.topWords(limit: 2), ["keyboard", "swift"])
        XCTAssertEqual(try repository.count(), 2)
        XCTAssertThrowsError(try repository.learn("not a word"))
    }

    func testDarwinNotificationSignalsSettingsRefresh() {
        let name = "com.glasstype.test.\(UUID().uuidString)"
        let delivered = expectation(description: "Darwin notification delivered")
        let signal = ExpectationSignal(delivered)
        let observer = DarwinNotificationCenter.observe(name: name) { signal.fulfill() }
        DarwinNotificationCenter.post(name: name)
        wait(for: [delivered], timeout: 1)
        observer.cancel()
    }
}

private final class FailureCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Error] = []
    var errors: [Error] { lock.lock(); defer { lock.unlock() }; return storage }
    func append(_ error: Error) { lock.lock(); storage.append(error); lock.unlock() }
}

private final class ExpectationSignal: @unchecked Sendable {
    private let expectation: XCTestExpectation
    init(_ expectation: XCTestExpectation) { self.expectation = expectation }
    func fulfill() { expectation.fulfill() }
}
