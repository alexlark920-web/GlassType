import Foundation

/// Candidate and glide commits insert a trailing space that the next key can reclaim.
public struct TypingErgonomics: Sendable, Equatable {
    public static let punctuation: Set<Character> = [".", ",", "!", "?", ":", ";"]

    public private(set) var isAutoSpaceActive = false

    public init() {}

    /// Word text followed by the automatic trailing space.
    public mutating func commitWord(_ word: String) -> String {
        isAutoSpaceActive = true
        return word + " "
    }

    /// Punctuation typed while the automatic space is still at the caret.
    /// The space is deleted first; the returned text is the mark plus a new space.
    public func punctuationInsertion(for input: String) -> String? {
        guard isAutoSpaceActive, input.count == 1, let mark = input.first, Self.punctuation.contains(mark) else { return nil }
        return String(mark) + " "
    }

    public mutating func activateAutoSpace() { isAutoSpaceActive = true }

    public mutating func clearAutoSpace() { isAutoSpaceActive = false }

    /// A single backspace removes only the automatic space.
    public mutating func consumeAutoSpace() -> Bool {
        guard isAutoSpaceActive else { return false }
        isAutoSpaceActive = false
        return true
    }
}

public enum SmartDoubleSpace {
    public static let maximumInterval: TimeInterval = 0.3

    /// Caller verifies that the preceding space was inserted by this keyboard
    /// at the same document/cursor. Replace that one space with the result.
    public static func replacement(contextBeforeInput context: String, elapsedSincePreviousSpace elapsed: TimeInterval) -> String? {
        guard elapsed.isFinite, elapsed >= 0, elapsed <= maximumInterval,
              context.hasSuffix(" "), !context.hasSuffix("  ") else { return nil }
        let text = String(context.dropLast())
        guard let last = text.last, last.isLetter else { return nil }
        let token = text.suffix(160).split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? ""
        let opening = Set("([{«“\"")
        let body = token.drop(while: { opening.contains($0) })
        let apostrophes = Set("'’ʼ")
        guard !body.isEmpty, body.count <= 64, body.first?.isLetter == true,
              body.allSatisfy({ $0.isLetter || apostrophes.contains($0) }) else { return nil }
        return ". "
    }
}

public enum PunctuationSpacing {
    private static let closingMarks = Set(".,!?;:…)]}»”٪%")

    /// Adds a word boundary before a letter after sentence punctuation or a
    /// closing delimiter. Opening marks, apostrophes and word-joining hyphens
    /// deliberately do not create a space.
    public static func prefixBeforeLetter(after context: String?) -> String {
        guard let context, let last = context.last, !last.isWhitespace else { return "" }
        if last == "." {
            let token = String(context.suffix(64).split(whereSeparator: { $0.isWhitespace }).last ?? "")
            // Avoid breaking a URL, email, or dotted identifier while it is
            // still being typed. Plain sentence-final dots are separated.
            if token.contains("@") || token.contains("://") || token.dropLast().contains(".") { return "" }
            return " "
        }
        if closingMarks.contains(last) { return " " }
        if last == "\"", let beforeQuote = context.dropLast().last,
           beforeQuote.isLetter || beforeQuote.isNumber || ".!?…)]}".contains(beforeQuote) {
            return " "
        }
        return ""
    }
}

public struct WordDeletionPlan {
    public let deletedText: String
    public var characterCount: Int { deletedText.count }
    public let contextBeforeDeletion: String

    /// Remove trailing spaces and the preceding word/symbol group. Never cross
    /// a newline or an unknown left edge of a host's truncated context.
    public static func make(contextBeforeInput context: String, contextIsComplete: Bool = false,
                            maximumCharacters: Int = 128) -> WordDeletionPlan? {
        guard !context.isEmpty, maximumCharacters > 0 else { return nil }
        let limit = min(maximumCharacters, 512)
        let characters = Array(context.suffix(limit + 1))
        guard let last = characters.last, !last.isNewline else { return nil }
        var start = characters.count
        while start > 0 && characters[start - 1].isWhitespace && !characters[start - 1].isNewline { start -= 1 }
        if start == 0 { return nil }
        if characters[start - 1].isNewline {
            // Only the horizontal whitespace after the last line break.
            let deleted = String(characters[start...])
            guard !deleted.isEmpty, deleted.count <= limit else { return nil }
            return WordDeletionPlan(deletedText: deleted, contextBeforeDeletion: context)
        }
        let wordLike: (Character) -> Bool = { $0.isLetter || $0.isNumber || ["'", "’", "ʼ", "_"].contains(String($0)) }
        // First consume trailing punctuation/emoji, then a word immediately
        // attached to it ("hello!"), without crossing whitespace/newlines.
        while start > 0 && !characters[start - 1].isWhitespace && !wordLike(characters[start - 1]) { start -= 1 }
        while start > 0 && wordLike(characters[start - 1]) { start -= 1 }
        guard start < characters.count else { return nil }
        let deleted = String(characters[start...])
        guard deleted.count <= limit else { return nil }
        let reachedContextStart = start == 0
        let fullContextVisible = context.count <= limit + 1
        guard !reachedContextStart || (contextIsComplete && fullContextVisible) else { return nil }
        return WordDeletionPlan(deletedText: deleted, contextBeforeDeletion: context)
    }
}

public struct TextDeletionUndo {
    public let deletedText: String
    private let before: String
    private let after: String?
    private let document: String
    public init(deletedText: String, before: String, after: String?, document: String) {
        self.deletedText = deletedText
        self.before = String(before.suffix(192))
        self.after = after.map { String($0.prefix(32)) }
        self.document = document
    }
    public func matches(before: String?, after: String?, document: String, hasSelection: Bool) -> Bool {
        guard !hasSelection, self.document == document, let before else { return false }
        return String(before.suffix(192)) == self.before && after.map({ String($0.prefix(32)) }) == self.after
    }
}

public enum SentenceCapitalization {
    /// Shift follows only the last four characters: the start of the field,
    /// a newline, or a sentence mark (`. `, `? `, `! `, or `…`). The rest of
    /// `documentContextBeforeInput` is never scanned.
    public static func shouldCapitalize(contextBeforeInput context: String?) -> Bool {
        guard let context else { return false }
        if context.isEmpty { return true }
        let probe = context.suffix(5)
        if probe.count < 5, !probe.contains(where: { $0.isLetter || $0.isNumber }) { return true }
        let tail = probe.count > 4 ? probe.dropFirst() : Substring(probe)
        if tail.last?.isNewline == true { return true }
        var cursor = tail.endIndex
        while cursor > tail.startIndex {
            let previous = tail.index(before: cursor)
            let character = tail[previous]
            if character.isNewline { return true }
            if !character.isWhitespace { break }
            cursor = previous
        }
        let hasSeparator = tail.last?.isWhitespace == true && tail.last?.isNewline != true
        let closers: Set<Character> = [")", "]", "»", "”", "\"", "'", "’"]
        while cursor > tail.startIndex {
            let previous = tail.index(before: cursor)
            let character = tail[previous]
            if closers.contains(character) { cursor = previous; continue }
            break
        }
        guard cursor > tail.startIndex else { return false }
        switch tail[tail.index(before: cursor)] {
        case "!", "?", "…": return true
        case ".": return hasSeparator
        default: return false
        }
    }
}
