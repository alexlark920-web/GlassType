import Foundation

public enum SmartDoubleSpace {
    /// Caller verifies that the preceding space was inserted by this keyboard
    /// at the same document/cursor. Replace that one space with the result.
    public static func replacement(contextBeforeInput context: String, elapsedSincePreviousSpace elapsed: TimeInterval) -> String? {
        guard elapsed.isFinite, elapsed >= 0, elapsed <= 0.7,
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
    /// Capitalize after a completed sentence + separator, not inside decimals,
    /// domains or identifiers. Nil means the host cannot supply safe context.
    public static func shouldCapitalize(contextBeforeInput context: String?) -> Bool {
        guard let context else { return false }
        if context.isEmpty { return true }
        let suffix = String(context.suffix(160))
        if suffix.last?.isNewline == true { return true }
        let hasSeparator = suffix.last?.isWhitespace == true
        let trimmed = suffix.reversed().drop(while: { $0.isWhitespace && !$0.isNewline })
        guard let final = trimmed.first else { return true }
        if final.isNewline { return true }
        let closing = Set(")] }»”\"'’".filter { !$0.isWhitespace })
        let characters = Array(trimmed.drop(while: { closing.contains($0) }))
        guard let mark = characters.first, [".", "!", "?", "…"].contains(String(mark)) else { return false }
        if mark == "." && !hasSeparator { return false }
        let terminators = Set(".!?…")
        let preceding = String(characters.drop(while: { terminators.contains($0) }).reversed())
        let token = preceding.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? ""
        if mark == "." {
            if token.contains("@") || token.contains("://") { return false }
            // Domain-looking dotted tokens differ from a number or version
            // followed by a sentence-ending dot and a separator.
            if token.contains("."), let tail = token.split(separator: ".").last,
               !tail.isEmpty, tail.allSatisfy(\.isLetter) { return false }
        }
        return true
    }
}
