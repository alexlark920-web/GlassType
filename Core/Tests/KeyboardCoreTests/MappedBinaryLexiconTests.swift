import Foundation
import XCTest
@testable import KeyboardCore

final class MappedBinaryLexiconTests: XCTestCase {
    private func lexicon(_ language: KeyboardLanguage) throws -> MappedBinaryLexicon {
        try MappedBinaryLexicon(bundledLanguage: language)
    }

    func testExactLookupAcrossLanguagesAndMultibyteUTF8() throws {
        XCTAssertTrue(try lexicon(.english).contains("keyboard"))
        let russian = try lexicon(.russian)
        XCTAssertTrue(russian.contains("ещё"))
        XCTAssertTrue(russian.contains("объект"))
        let ukrainian = try lexicon(.ukrainian)
        XCTAssertTrue(ukrainian.contains("євро"))
        XCTAssertTrue(ukrainian.contains("інтернет"))
        XCTAssertFalse(ukrainian.contains("объект"))
    }

    func testMissingWordsEmptyInputAndPrefixes() throws {
        let dictionary = try lexicon(.english)
        XCTAssertFalse(dictionary.contains(""))
        XCTAssertFalse(dictionary.contains("notawordthatshouldexist"))
        XCTAssertFalse(dictionary.contains("keyboar"))
        XCTAssertTrue(dictionary.findWords(matchingPrefix: "keyboard", limit: 10).contains("keyboard"))
        XCTAssertTrue(dictionary.findWords(matchingPrefix: "zzzz", limit: 10).isEmpty)
        XCTAssertTrue(dictionary.findWords(matchingPrefix: "k", limit: 0).isEmpty)
    }

    func testRawUTF8ContainsAndLookupThroughMappedFile() throws {
        let dictionary = try lexicon(.russian)
        let bytes = Array("ещё".utf8)
        XCTAssertTrue(bytes.withUnsafeBufferPointer { dictionary.contains($0) })
    }

    func testMappedInitializationUnderOneMillisecond() throws {
        let start = ProcessInfo.processInfo.systemUptime
        _ = try MappedBinaryLexicon(bundledLanguage: .english)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
#if DEBUG
        XCTAssertLessThan(elapsed, 0.05, "Debug mapped initialization took \(elapsed * 1_000) ms")
#else
        XCTAssertLessThan(elapsed, 0.001, "Mapped initialization took \(elapsed * 1_000) ms")
#endif
    }

    func testTenThousandRawLookupsUnderFiveMilliseconds() throws {
        let dictionary = try lexicon(.english)
        let bytes = Array("keyboard".utf8)
        let start = ProcessInfo.processInfo.systemUptime
        let found = bytes.withUnsafeBufferPointer { buffer in
            (0..<10_000).reduce(into: 0) { count, _ in
                if dictionary.contains(buffer) { count += 1 }
            }
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        XCTAssertEqual(found, 10_000)
#if DEBUG
        XCTAssertLessThan(elapsed, 0.05, "Debug 10,000 lookups took \(elapsed * 1_000) ms")
#else
        XCTAssertLessThan(elapsed, 0.005, "10,000 lookups took \(elapsed * 1_000) ms")
#endif
    }
}
