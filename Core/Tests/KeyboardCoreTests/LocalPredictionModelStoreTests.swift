import XCTest
@testable import KeyboardCore

final class LocalPredictionModelStoreTests: XCTestCase {
    func testProfilePersistsInInjectedLocalContainerAndCanBeReset() {
        let suite = "GlassTypePredictionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = LocalPredictionModelStore(defaults: defaults, key: "profile")
        first.observe(context: "we really", nextWord: "hello", language: .english)
        let second = LocalPredictionModelStore(defaults: defaults, key: "profile")
        XCTAssertEqual(second.snapshot().nextWords(after: "we really", language: .english), ["hello"])
        second.reset()
        XCTAssertTrue(second.snapshot().nextWords(after: "we really", language: .english).isEmpty)
        XCTAssertNil(defaults.data(forKey: "profile"))
    }

    func testProfileStorageRejectsOversizedSerializedData() {
        let suite = "GlassTypePredictionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(repeating: 0x41, count: 64 * 1024), forKey: "profile")
        let store = LocalPredictionModelStore(defaults: defaults, key: "profile")
        XCTAssertTrue(store.snapshot().nextWords(after: "some context", language: .english).isEmpty)
    }
}
