import Foundation

/// Read-only byte trie backed by a memory-mapped bundled resource.
/// The file remains retained for the full lifetime of every raw-byte access.
public final class MappedBinaryLexicon: @unchecked Sendable {
    private static let nodeSize = 6
    private static let terminal: UInt8 = 0x01
    private static let hasSibling: UInt8 = 0x02

    private let data: Data

    public convenience init(bundledLanguage: KeyboardLanguage) throws {
        guard let url = Bundle.module.url(forResource: "lexicon_" + bundledLanguage.rawValue,
                                          withExtension: "trie") else {
            throw CocoaError(.fileNoSuchFile)
        }
        try self.init(url: url)
    }

    public init(url: URL) throws {
        let mapped = try Data(contentsOf: url, options: .mappedIfSafe)
        guard mapped.count >= Self.nodeSize,
              mapped.count % Self.nodeSize == 0,
              mapped[0] == 0,
              Self.readUInt32(mapped, at: 2) == 0 || Self.validOffset(Self.readUInt32(mapped, at: 2), count: mapped.count) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = mapped
    }

    /// Searches directly through UTF-8 bytes; this overload creates no String.
    public func contains(_ utf8Bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        guard !utf8Bytes.isEmpty else { return false }
        return data.withUnsafeBytes { raw in
            guard let bytes = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
            var parent = 0
            for (position, target) in utf8Bytes.enumerated() {
                var child = Self.childOffset(bytes, parent: parent)
                var found: Int?
                while child != 0 {
                    guard child + Self.nodeSize <= raw.count else { return false }
                    let current = bytes[child]
                    if current == target { found = child; break }
                    if current > target { break }
                    child = bytes[child + 1] & Self.hasSibling == 0 ? 0 : child + Self.nodeSize
                }
                guard let found else { return false }
                if position == utf8Bytes.count - 1 { return bytes[found + 1] & Self.terminal != 0 }
                parent = found
            }
            return false
        }
    }

    public func contains(_ word: String) -> Bool {
        let normalized = word.precomposedStringWithCanonicalMapping.lowercased()
        if let result = normalized.utf8.withContiguousStorageIfAvailable({ contains($0) }) { return result }
        let bytes = Array(normalized.utf8)
        return bytes.withUnsafeBufferPointer { contains($0) }
    }

    /// Returns at most `limit` words in byte-lexicographic order.
    public func findWords(matchingPrefix prefix: String, limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        let normalized = prefix.precomposedStringWithCanonicalMapping.lowercased()
        return data.withUnsafeBytes { raw in
            guard let bytes = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return [] }
            var node = 0
            for target in normalized.utf8 {
                var child = Self.childOffset(bytes, parent: node)
                var found = 0
                while child != 0 {
                    guard child + Self.nodeSize <= raw.count else { return [] }
                    if bytes[child] == target { found = child; break }
                    if bytes[child] > target { break }
                    child = bytes[child + 1] & Self.hasSibling == 0 ? 0 : child + Self.nodeSize
                }
                guard found != 0 else { return [] }
                node = found
            }

            var result: [String] = []
            var path = Array(normalized.utf8)
            if !normalized.isEmpty, bytes[node + 1] & Self.terminal != 0 { result.append(normalized) }
            func visit(_ parent: Int) {
                guard result.count < limit else { return }
                var child = Self.childOffset(bytes, parent: parent)
                while child != 0 && result.count < limit {
                    guard child + Self.nodeSize <= raw.count else { return }
                    path.append(bytes[child])
                    if bytes[child + 1] & Self.terminal != 0,
                       let word = String(bytes: path, encoding: .utf8) { result.append(word) }
                    visit(child)
                    path.removeLast()
                    child = bytes[child + 1] & Self.hasSibling == 0 ? 0 : child + Self.nodeSize
                }
            }
            if result.count >= limit { return result }
            if normalized.isEmpty {
                visit(0)
            } else if Self.readUInt32(bytes, at: node + 2) != 0 {
                visit(node)
            }
            return result
        }
    }

    /// Diagnostic/compatibility enumeration. Callers should prefer prefix lookup.
    public func allWords() -> [String] { findWords(matchingPrefix: "", limit: Int.max) }

    private static func childOffset(_ bytes: UnsafePointer<UInt8>, parent: Int) -> Int {
        Int(readUInt32(bytes, at: parent + 2))
    }
    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }
    private static func readUInt32(_ bytes: UnsafePointer<UInt8>, at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }
    private static func validOffset(_ offset: UInt32, count: Int) -> Bool {
        offset >= UInt32(nodeSize) && Int(offset) < count && offset % UInt32(nodeSize) == 0
    }
}
