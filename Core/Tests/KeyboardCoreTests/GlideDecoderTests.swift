import Foundation
import CoreGraphics
import XCTest
@testable import KeyboardCore

final class GlideDecoderTests: XCTestCase {
    private let decoder = GlideDecoder()
    private func centers(_ language: KeyboardLanguage) -> [String: CGPoint] {
        let layout = KeyboardGeometry.make(bounds: CGRect(x: 0, y: 0, width: 385, height: 225), language: language)
        return Dictionary(uniqueKeysWithValues: layout.keys.compactMap { key -> (String, CGPoint)? in
            guard let letter = key.role.character, letter.allSatisfy(\.isLetter) else { return nil }
            return (letter, key.center)
        })
    }

    private func path(_ word: String, language: KeyboardLanguage) -> [CGPoint] {
        let geometry = centers(language)
        return word.map { geometry[String($0)]! }
    }
    func testDirectEnglishPath() {
        XCTAssertEqual(decoder.decode(points: path("hello", language: .english), keyCenters: centers(.english), language: .english).first, "hello")
    }
    func testNoisyContinuousStrokesOnPortraitAndLandscapeLayouts() {
        let examples: [(String, KeyboardLanguage)] = [("hello", .english), ("thanks", .english), ("world", .english), ("keyboard", .english),
            ("привет", .russian), ("как", .russian), ("хорошо", .russian), ("спасибо", .russian),
            ("привіт", .ukrainian), ("дякую", .ukrainian), ("сьогодні", .ukrainian), ("добре", .ukrainian)]
        for (word, language) in examples {
            for size in [CGSize(width: 320, height: 225), CGSize(width: 750, height: 155)] {
                let layout = KeyboardGeometry.make(bounds: CGRect(origin: .zero, size: size), language: language)
                let centers = Dictionary(uniqueKeysWithValues: layout.keys.compactMap { key -> (String, CGPoint)? in
                    guard let text = key.role.character, text.allSatisfy(\.isLetter) else { return nil }
                    return (text, key.center)
                })
                let anchors = word.map { centers[String($0)]! }
                var trace: [CGPoint] = []
                for (index, pair) in zip(anchors, anchors.dropFirst()).enumerated() {
                    for step in 0..<16 {
                        let t = CGFloat(step) / 16
                        let wave = t * CGFloat.pi * 2
                        let dx = layout.pitch.width * 0.15 + 1.4 * sin(wave + CGFloat(index))
                        let dy = -layout.pitch.height * 0.10 + 1.2 * cos(wave)
                        let x = pair.0.x + (pair.1.x - pair.0.x) * t + dx
                        let y = pair.0.y + (pair.1.y - pair.0.y) * t + dy
                        trace.append(CGPoint(x: x, y: y))
                    }
                }
                trace.append(CGPoint(x: anchors.last!.x + layout.pitch.width * 0.15, y: anchors.last!.y - layout.pitch.height * 0.10))
                XCTAssertTrue(decoder.decode(points: trace, keyCenters: centers, language: language).contains(word), "\(word) \(size)")
            }
        }
    }
    func testDwellJitterDoesNotTurnAWordIntoAnOverlongPath() {
        let geometry = centers(.english), start = geometry["h"]!
        let dwell = (0..<100).map { index in
            CGPoint(x: start.x + 1.6 * sin(CGFloat(index)), y: start.y + 1.6 * cos(CGFloat(index)))
        }
        XCTAssertEqual(decoder.decode(points: dwell + path("hello", language: .english), keyCenters: geometry, language: .english).first, "hello")
    }
    func testDirectRussianPath() {
        XCTAssertEqual(decoder.decode(points: path("привет", language: .russian), keyCenters: centers(.russian), language: .russian).first, "привет")
    }
    func testDirectUkrainianPath() {
        XCTAssertEqual(decoder.decode(points: path("привіт", language: .ukrainian), keyCenters: centers(.ukrainian), language: .ukrainian).first, "привіт")
    }
    func testConsecutiveRepeatedLettersDoNotRequireLoops() {
        let trace = path("leter", language: .english)
        XCTAssertEqual(decoder.decode(points: trace, keyCenters: centers(.english), language: .english).first, "letter")
    }
    func testSmallFingerOffsetIsTolerated() {
        let trace = path("thanks", language: .english).map { CGPoint(x: $0.x + 3, y: $0.y - 2) }
        XCTAssertEqual(decoder.decode(points: trace, keyCenters: centers(.english), language: .english).first, "thanks")
    }
    func testPersonalWordCanExtendVocabulary() {
        let trace = path("qwerty", language: .english)
        XCTAssertEqual(decoder.decode(points: trace, keyCenters: centers(.english), language: .english, extraWords: ["qwerty"]).first, "qwerty")
    }
    func testInsufficientMovementAndInvalidGeometryAreRejected() {
        let geometry = centers(.english)
        XCTAssertTrue(decoder.decode(points: [], keyCenters: geometry, language: .english).isEmpty)
        XCTAssertTrue(decoder.decode(points: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)], keyCenters: geometry, language: .english).isEmpty)
        XCTAssertTrue(decoder.decode(points: path("hello", language: .english), keyCenters: [:], language: .english).isEmpty)
        XCTAssertTrue(decoder.decode(points: [CGPoint(x: CGFloat.nan, y: 0), .zero], keyCenters: geometry, language: .english).isEmpty)
    }
    func testOffKeyboardScribbleAndExcessiveInputAreRejected() {
        let geometry = centers(.english)
        let trace = [CGPoint(x: 0, y: 0), CGPoint(x: 4000, y: 4000), CGPoint(x: 200, y: 50)]
        XCTAssertTrue(decoder.decode(points: trace, keyCenters: geometry, language: .english).isEmpty)
        XCTAssertTrue(decoder.decode(points: Array(repeating: .zero, count: 5000), keyCenters: geometry, language: .english).isEmpty)
    }
    func testResultsAreBoundedAndUnique() {
        let result = decoder.decode(points: path("hello", language: .english), keyCenters: centers(.english), language: .english, extraWords: ["hello", "hello", "Hello"], limit: 100)
        XCTAssertFalse(result.isEmpty)
        XCTAssertLessThanOrEqual(result.count, 3)
        XCTAssertEqual(result.count, Set(result).count)
        XCTAssertTrue(decoder.decode(points: path("hello", language: .english), keyCenters: centers(.english), language: .english, limit: 0).isEmpty)
    }
    func testEveryLanguageHasARealBaselineVocabulary() {
        for language in KeyboardLanguage.allCases {
            XCTAssertGreaterThan(Set(GlideDecoder.words(for: language)).count, 100)
        }
    }
    func testUserReportedWordsOnContinuousTrajectoriesAndActualLayouts() {
        let cases: [(String, KeyboardLanguage)] = [("hello", .english), ("привет", .russian), ("как", .russian), ("привіт", .ukrainian), ("як", .ukrainian)]
        for (word, language) in cases {
            for size in [CGSize(width: 312, height: 225), CGSize(width: 385, height: 225), CGSize(width: 750, height: 155)] {
                let layout = KeyboardGeometry.make(bounds: CGRect(origin: .zero, size: size), language: language)
                let centers = Dictionary(uniqueKeysWithValues: layout.keys.compactMap { key -> (String, CGPoint)? in
                    guard let letter = key.role.character, letter.allSatisfy(\.isLetter) else { return nil }
                    return (letter, key.center)
                })
                let anchors = word.map { centers[String($0)]! }
                var trace: [CGPoint] = []
                for (a, b) in zip(anchors, anchors.dropFirst()) {
                    for step in 0..<12 {
                        let t = CGFloat(step) / 12
                        trace.append(CGPoint(x: a.x + (b.x - a.x) * t + 2 * sin(t * .pi), y: a.y + (b.y - a.y) * t + 1.5 * cos(t * .pi)))
                    }
                }
                trace.append(anchors.last!)
                XCTAssertEqual(decoder.decode(points: trace, keyCenters: centers, language: language).first, word, "\(word) at \(size)")
            }
        }
    }
    func testLargeDictionaryWordsAreNotCutOffAtFirst512Entries() {
        let cases: [(String, KeyboardLanguage)] = [("keyboard", .english), ("клавиатура", .russian), ("клавіатура", .ukrainian)]
        for (word, language) in cases {
            XCTAssertGreaterThan(OfflineLexicon.frequencyIndex(word: word, language: language) ?? 0, 512)
            XCTAssertEqual(decoder.decode(points: path(word, language: language), keyCenters: centers(language), language: language).first, word)
        }
    }
    func testActivationWaitsForMovementAndAnotherKeyWithoutPrematureVeto() {
        let origin = CGPoint(x: 20, y: 20)
        XCTAssertFalse(GlideActivation.shouldBegin(start: origin, current: origin, startKey: 0, currentKey: 0))
        XCTAssertFalse(GlideActivation.shouldBegin(start: origin, current: CGPoint(x: 25, y: 20), startKey: 0, currentKey: 1))
        XCTAssertFalse(GlideActivation.shouldBegin(start: origin, current: CGPoint(x: 30, y: 20), startKey: 0, currentKey: 0))
        XCTAssertTrue(GlideActivation.shouldBegin(start: origin, current: CGPoint(x: 30, y: 20), startKey: 0, currentKey: 1))
        XCTAssertFalse(GlideActivation.shouldBegin(start: origin, current: CGPoint(x: 30, y: 20), startKey: nil, currentKey: 1))
    }

}
