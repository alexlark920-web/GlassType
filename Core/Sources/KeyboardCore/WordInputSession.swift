import Foundation

/// A bounded, transient cursor fingerprint. Never persisted or sent anywhere.
/// An unavailable context is usable only when the host confirms an empty field.
public struct InputContextSnapshot: Equatable {
    public let before: String?
    public let after: String?
    public let document: String
    public let hasSelection: Bool
    public var isUsable: Bool { before != nil && !hasSelection }

    public init(before: String?, after: String?, document: String, hasSelection: Bool, fieldIsEmpty: Bool = false) {
        self.before = (before ?? (fieldIsEmpty ? "" : nil)).map { String($0.suffix(192)) }
        self.after = after.map { String($0.prefix(32)) }
        self.document = document; self.hasSelection = hasSelection
    }
    public func matches(_ current: InputContextSnapshot) -> Bool {
        isUsable && current.isUsable && self == current
    }
}

/// Owns only the most recently inserted word and its automatic trailing space.
/// Manual spaces and unrelated text are never trimmed by this record.
public struct CompletedWordInsertion {
    public enum Origin: Equatable { case glide, suggestion }
    public let origin: Origin
    public let insertedText: String
    private let context: InputContextSnapshot

    public init?(origin: Origin, insertedText: String, context: InputContextSnapshot) {
        guard context.isUsable, insertedText.hasSuffix(" "), insertedText.count <= 160,
              context.before?.hasSuffix(insertedText) == true else { return nil }
        self.origin = origin; self.insertedText = insertedText; self.context = context
    }
    public func matches(_ current: InputContextSnapshot) -> Bool { context.matches(current) }
    public func deletionCount(in current: InputContextSnapshot) -> Int? {
        origin == .glide && matches(current) ? insertedText.count : nil
    }
    public func spaceDeletionCount(before punctuation: String, in current: InputContextSnapshot) -> Int {
        let closing = ".,!?:;…)]}»”%"
        return punctuation.count == 1 && punctuation.first.map({ closing.contains($0) }) == true && matches(current) ? 1 : 0
    }
}

/// Keeps keystrokes behind a background word decode in their original order.
/// Tokens prevent a late worker from committing into another cursor/document.
public struct PendingInputSequence<Command> {
    public private(set) var token: UInt?
    public private(set) var context: InputContextSnapshot?
    private var serial: UInt = 0
    private var commands: [Command] = []
    private var head = 0
    public init() { commands.reserveCapacity(16) }
    public var isBusy: Bool { token != nil }
    public mutating func begin(in context: InputContextSnapshot) -> UInt {
        precondition(!isBusy)
        serial &+= 1; token = serial; self.context = context
        return serial
    }
    public mutating func deferIfBusy(_ command: Command) -> Bool {
        guard isBusy else { return false }
        enqueue(command); return true
    }
    public mutating func enqueue(_ command: Command) { commands.append(command) }
    public mutating func next() -> Command? {
        guard !isBusy, head < commands.count else { return nil }
        let value = commands[head]; head += 1
        if head == commands.count { commands.removeAll(keepingCapacity: true); head = 0 }
        return value
    }
    public mutating func finish(token: UInt, in current: InputContextSnapshot) -> Bool {
        guard self.token == token else { return false }
        let valid = context?.matches(current) == true
        self.token = nil; context = nil
        if !valid { cancel() }
        return valid
    }
    public mutating func cancel() {
        serial &+= 1; token = nil; context = nil
        commands.removeAll(keepingCapacity: true); head = 0
    }

    /// Invalidate an in-flight worker but retain input events that arrived
    /// while it ran. The main-thread owner can drain those events immediately.
    public mutating func invalidateWorkPreservingCommands() {
        serial &+= 1; token = nil; context = nil
    }

    /// Remove stale deferred work without disturbing the order of live input.
    public mutating func removeQueued(where shouldRemove: (Command) -> Bool) {
        guard head < commands.count else { return }
        commands = Array(commands[head...].filter { !shouldRemove($0) })
        head = 0
    }
}

public enum EnabledKeyboardLanguages {
    public static func normalized(_ languages: [KeyboardLanguage]) -> [KeyboardLanguage] {
        let unique = KeyboardLanguage.allCases.filter { languages.contains($0) }
        return unique.isEmpty ? [.english] : unique
    }
    /// Refuses to disable the last language. The caller reflects this in its UI.
    public static func setting(_ language: KeyboardLanguage, enabled: Bool, in languages: [KeyboardLanguage]) -> [KeyboardLanguage] {
        var result = normalized(languages)
        if enabled { result.append(language) }
        else if result.count > 1 { result.removeAll { $0 == language } }
        return normalized(result)
    }
}
