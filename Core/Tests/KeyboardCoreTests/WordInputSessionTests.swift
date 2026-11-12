import XCTest
@testable import KeyboardCore

final class WordInputSessionTests: XCTestCase {
    private func context(_ before: String?, after: String? = nil, document: String = "A", selected: Bool = false, empty: Bool = false) -> InputContextSnapshot {
        .init(before: before, after: after, document: document, hasSelection: selected, fieldIsEmpty: empty)
    }
    func testMissingContextIsAllowedOnlyInConfirmedEmptyField() {
        XCTAssertFalse(context(nil).isUsable)
        XCTAssertTrue(context(nil, empty: true).matches(context("")))
        XCTAssertFalse(context(nil, empty: true).matches(context(nil)))
        XCTAssertFalse(context("", selected: true).isUsable)
    }
    func testPunctuationTrimsOnlyTheAutomaticSpaceForBothWordSources() {
        for origin in [CompletedWordInsertion.Origin.glide, .suggestion] {
            let current = context("Привет ")
            let insertion = CompletedWordInsertion(origin: origin, insertedText: "Привет ", context: current)!
            var ergonomics = TypingErgonomics()
            _ = ergonomics.commitWord("Привет")
            for mark in [".", ",", "!", "?", ":", ";"] {
                var text = current.before!
                XCTAssertEqual(insertion.spaceDeletionCount(before: mark, in: current), 1)
                text.removeLast(insertion.spaceDeletionCount(before: mark, in: current))
                text += ergonomics.punctuationInsertion(for: mark)!
                XCTAssertEqual(text, "Привет" + mark + " ")
                XCTAssertTrue(ergonomics.isAutoSpaceActive)
            }
            for mark in ["…", "»", ")"] {
                var text = current.before!
                text.removeLast(insertion.spaceDeletionCount(before: mark, in: current))
                text += mark
                XCTAssertEqual(text, "Привет" + mark)
                XCTAssertNil(ergonomics.punctuationInsertion(for: mark))
            }
            for value in [" ", "\n", "a", "1", "(", "", "!?", "👋"] {
                XCTAssertEqual(insertion.spaceDeletionCount(before: value, in: current), 0)
                XCTAssertNil(ergonomics.punctuationInsertion(for: value))
            }
        }
    }

    func testSingleBackspaceRemovesOnlyTheAutomaticSpace() {
        var ergonomics = TypingErgonomics()
        XCTAssertEqual(ergonomics.commitWord("hello"), "hello ")
        XCTAssertTrue(ergonomics.isAutoSpaceActive)
        XCTAssertTrue(ergonomics.consumeAutoSpace())
        XCTAssertFalse(ergonomics.isAutoSpaceActive)
        XCTAssertFalse(ergonomics.consumeAutoSpace())
        XCTAssertNil(ergonomics.punctuationInsertion(for: "."))
    }
    func testManualSpacesAndCursorChangesInvalidateAutomaticTrimming() {
        let record = CompletedWordInsertion(origin: .glide, insertedText: "hello ", context: context("say hello ", after: "tail"))!
        for changed in [context("say hello  ", after: "tail"), context("say hello", after: " tail"),
                        context("say hello ", after: "tail", document: "B"), context("say hello ", after: "tail", selected: true),
                        context("say hello ", after: "changed"), context(nil)] {
            XCTAssertEqual(record.spaceDeletionCount(before: ".", in: changed), 0)
            XCTAssertNil(record.deletionCount(in: changed))
        }
    }
    func testFirstBackspaceAfterCandidateCommitUsesOrdinarySingleCharacterDeletion() {
        for origin in [CompletedWordInsertion.Origin.glide, .suggestion] {
            let current = context("👋 привет мир ")
            let insertion = CompletedWordInsertion(origin: origin, insertedText: " мир ", context: current)!
            // nil means the controller falls through to textDocumentProxy.deleteBackward(),
            // removing only the trailing automatic space on this first press.
            XCTAssertNil(insertion.deletionCount(in: current))
        }
    }
    func testFollowingPunctuationAndLettersWaitForDecodeInOriginalOrder() {
        var sequence = PendingInputSequence<String>()
        let token = sequence.begin(in: context("say "))
        XCTAssertTrue(sequence.deferIfBusy("."))
        XCTAssertTrue(sequence.deferIfBusy(" "))
        XCTAssertTrue(sequence.deferIfBusy("N"))
        XCTAssertNil(sequence.next())
        XCTAssertTrue(sequence.finish(token: token, in: context("say ")))
        var text = "say hello "
        let record = CompletedWordInsertion(origin: .glide, insertedText: "hello ", context: context(text))!
        var ergonomics = TypingErgonomics()
        _ = ergonomics.commitWord("hello")
        let punctuation = sequence.next()!
        text.removeLast(record.spaceDeletionCount(before: punctuation, in: context(text)))
        text += ergonomics.punctuationInsertion(for: punctuation)!
        while let next = sequence.next() { text += next }
        XCTAssertEqual(text, "say hello.  N")
        XCTAssertFalse(sequence.isBusy)
    }
    func testSecondStrokeCanWaitBehindTheFirstWithoutLosingLaterInput() {
        var sequence = PendingInputSequence<String>()
        let first = sequence.begin(in: context(""))
        sequence.enqueue("second stroke"); sequence.enqueue("backspace")
        XCTAssertTrue(sequence.finish(token: first, in: context("")))
        XCTAssertEqual(sequence.next(), "second stroke")
        let second = sequence.begin(in: context("Hello "))
        XCTAssertFalse(sequence.finish(token: first, in: context("")))
        XCTAssertEqual(sequence.token, second)
        XCTAssertNil(sequence.next())
        XCTAssertTrue(sequence.finish(token: second, in: context("Hello ")))
        XCTAssertEqual(sequence.next(), "backspace")
    }
    func testLateDecodeCannotCommitAfterCursorOrDocumentChanged() {
        var sequence = PendingInputSequence<String>()
        let old = sequence.begin(in: context("old "))
        sequence.enqueue("typing")
        XCTAssertFalse(sequence.finish(token: old, in: context("new ")))
        XCTAssertNil(sequence.next())
        let fresh = sequence.begin(in: context("new ", document: "B"))
        sequence.cancel()
        XCTAssertFalse(sequence.finish(token: fresh, in: context("new ", document: "B")))
        XCTAssertFalse(sequence.isBusy)
    }
    func testBackspaceCanCancelPendingDecodeAndDrainOtherContactsImmediately() {
        var sequence = PendingInputSequence<String>()
        let token = sequence.begin(in: context("before "))
        sequence.enqueue("typed-a")
        sequence.enqueue("stale-glide")
        sequence.enqueue("typed-b")
        sequence.invalidateWorkPreservingCommands()
        sequence.removeQueued { $0 == "stale-glide" }
        XCTAssertFalse(sequence.isBusy)
        XCTAssertEqual(sequence.next(), "typed-a")
        XCTAssertEqual(sequence.next(), "typed-b")
        XCTAssertNil(sequence.next())
        XCTAssertFalse(sequence.finish(token: token, in: context("before ")))
    }
    func testLanguageSelectionDeduplicatesAndKeepsAtLeastOneLanguage() {
        XCTAssertEqual(EnabledKeyboardLanguages.normalized([]), [.english])
        XCTAssertEqual(EnabledKeyboardLanguages.normalized([.russian, .russian, .english]), [.english, .russian])
        XCTAssertEqual(EnabledKeyboardLanguages.setting(.russian, enabled: false, in: [.russian]), [.russian])
        let enabled = EnabledKeyboardLanguages.setting(.english, enabled: false, in: [.english, .ukrainian])
        XCTAssertEqual(enabled, [.ukrainian])
        var state = InputState(language: .english)
        state.cycleLanguage(enabled: enabled, direction: .next)
        XCTAssertEqual(state.language, .ukrainian)
        state.cycleLanguage(enabled: enabled, direction: .previous)
        XCTAssertEqual(state.language, .ukrainian)
    }
}
