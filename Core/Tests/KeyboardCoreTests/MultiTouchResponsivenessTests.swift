import XCTest
@testable import KeyboardCore

final class MultiTouchResponsivenessTests: XCTestCase {
    func testOverlappingIndependentKeyContactsCommitEveryLetterInLiftOrder() {
        let geometry = KeyboardGeometry.make(bounds: CGRect(x: 0, y: 0, width: 390, height: 270), language: .english)
        let model = TouchRecognizer(geometry: geometry)
        let selected = geometry.keys.filter { ["a", "s", "d"].contains($0.role.character ?? "") }
        XCTAssertEqual(selected.count, 3)
        var contacts = selected.map { key -> (TextTouchSession, KeyboardKeyGeometry) in
            var session = TextTouchSession()
            session.begin(at: key.center, keyIndex: key.index, model: model)
            return (session, key)
        }
        XCTAssertTrue(contacts.allSatisfy { $0.0.phase == .tracking })

        var committed: [String] = []
        for index in contacts.indices.reversed() {
            let key = contacts[index].1
            if let result = contacts[index].0.end(at: key.center, model: model) {
                committed.append(geometry.keys[result].role.character!)
            }
        }
        XCTAssertEqual(committed, ["d", "s", "a"])
        XCTAssertTrue(contacts.allSatisfy { $0.0.phase == .ended })
    }

    func testRapidSequentialContactsOnSameKeyAreNotSuppressed() {
        let geometry = KeyboardGeometry.make(bounds: CGRect(x: 0, y: 0, width: 390, height: 270), language: .english)
        let model = TouchRecognizer(geometry: geometry)
        let key = try! XCTUnwrap(geometry.keys.first { $0.role.character == "a" })
        var committed: [String] = []
        for _ in 0..<12 {
            var session = TextTouchSession()
            session.begin(at: key.center, keyIndex: key.index, model: model)
            if let result = session.end(at: key.center, model: model) {
                committed.append(geometry.keys[result].role.character!)
            }
        }
        XCTAssertEqual(committed, Array(repeating: "a", count: 12))
    }
}
