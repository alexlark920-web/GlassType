import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#endif

/// A file mapped once for the lifetime of the owner. Hot paths read `base`
/// directly and never copy the mapping into a `Data` buffer or heap array.
final class StableMappedBytes: @unchecked Sendable {
    let base: UnsafePointer<UInt8>
    let count: Int
    private let storage: Storage

    private final class Storage {
        let address: UnsafeMutableRawPointer
        let length: Int
        let ownsAllocation: Bool

        init(address: UnsafeMutableRawPointer, length: Int, ownsAllocation: Bool) {
            self.address = address
            self.length = length
            self.ownsAllocation = ownsAllocation
        }

        deinit {
            if ownsAllocation {
                address.deallocate()
            } else {
                munmap(address, length)
            }
        }
    }

    init(url: URL) throws {
        if let mapped = Self.map(url) {
            storage = Storage(address: mapped.address, length: mapped.length, ownsAllocation: false)
            base = UnsafePointer(mapped.address.assumingMemoryBound(to: UInt8.self))
            count = mapped.length
            return
        }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        let address = UnsafeMutableRawPointer.allocate(byteCount: data.count, alignment: 16)
        data.copyBytes(to: address.bindMemory(to: UInt8.self, capacity: data.count), count: data.count)
        storage = Storage(address: address, length: data.count, ownsAllocation: true)
        base = UnsafePointer(address.assumingMemoryBound(to: UInt8.self))
        count = data.count
    }

    private static func map(_ url: URL) -> (address: UnsafeMutableRawPointer, length: Int)? {
        let fd = url.path.withCString { open($0, O_RDONLY) }
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_size > 0 else { return nil }
        let length = Int(info.st_size)
        let mapped = mmap(nil, length, PROT_READ, MAP_PRIVATE, fd, 0)
        guard let mapped, mapped != UnsafeMutableRawPointer(bitPattern: -1) else { return nil }
        return (mapped, length)
    }
}

/// Read-only byte trie backed by a memory-mapped bundled resource.
/// The mapping stays alive for every raw-byte access. Lookups never copy it.
public final class MappedBinaryLexicon: @unchecked Sendable {
    private static let nodeSize = 6
    private static let terminal: UInt8 = 0x01
    private static let hasSibling: UInt8 = 0x02

    private let mapped: StableMappedBytes

    public convenience init(bundledLanguage: KeyboardLanguage) throws {
        guard let url = Bundle.module.url(forResource: "lexicon_" + bundledLanguage.rawValue,
                                          withExtension: "trie") else {
            throw CocoaError(.fileNoSuchFile)
        }
        try self.init(url: url)
    }

    public init(url: URL) throws {
        let mapped = try StableMappedBytes(url: url)
        guard mapped.count >= Self.nodeSize,
              mapped.count % Self.nodeSize == 0,
              mapped.base[0] == 0,
              Self.readUInt32(mapped.base, at: 2) == 0 || Self.validOffset(Self.readUInt32(mapped.base, at: 2), count: mapped.count) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.mapped = mapped
    }

    /// Searches directly through UTF-8 bytes; this overload creates no String.
    public func contains(_ utf8Bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        guard !utf8Bytes.isEmpty else { return false }
        let bytes = mapped.base
        let rawCount = mapped.count
        var parent = 0
        for (position, target) in utf8Bytes.enumerated() {
            var child = Self.childOffset(bytes, parent: parent)
            var found: Int?
            while child != 0 {
                guard child + Self.nodeSize <= rawCount else { return false }
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

    public func contains(_ word: String) -> Bool {
        let normalized = word.precomposedStringWithCanonicalMapping.lowercased()
        if let result = normalized.utf8.withContiguousStorageIfAvailable({ contains($0) }) { return result }
        guard !normalized.utf8.isEmpty else { return false }
        var temporary = [UInt8]()
        temporary.reserveCapacity(normalized.utf8.underestimatedCount)
        for byte in normalized.utf8 { temporary.append(byte) }
        return temporary.withUnsafeBufferPointer { contains($0) }
    }

    /// Returns at most `limit` words in byte-lexicographic order.
    /// The traversal path stays in a stack buffer. Only emitted words become Strings.
    public func findWords(matchingPrefix prefix: String, limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        let normalized = prefix.precomposedStringWithCanonicalMapping.lowercased()
        let prefixCount = normalized.utf8.count
        let capacity = prefixCount + 96
        guard prefixCount <= 160, capacity <= 256 else { return [] }
        let bytes = mapped.base
        let rawCount = mapped.count
        return withUnsafeTemporaryAllocation(of: UInt8.self, capacity: capacity) { path in
            guard let pathBase = path.baseAddress else { return [] }
            var pathCount = 0
            for byte in normalized.utf8 {
                pathBase[pathCount] = byte
                pathCount += 1
            }

            var node = 0
            for index in 0..<pathCount {
                let target = pathBase[index]
                var child = Self.childOffset(bytes, parent: node)
                var found = 0
                while child != 0 {
                    guard child + Self.nodeSize <= rawCount else { return [] }
                    if bytes[child] == target { found = child; break }
                    if bytes[child] > target { break }
                    child = bytes[child + 1] & Self.hasSibling == 0 ? 0 : child + Self.nodeSize
                }
                guard found != 0 else { return [] }
                node = found
            }

            var result: [String] = []
            if pathCount > 0, bytes[node + 1] & Self.terminal != 0 {
                result.append(String(decoding: UnsafeBufferPointer(start: pathBase, count: pathCount), as: UTF8.self))
            }
            func visit(_ parent: Int) {
                guard result.count < limit else { return }
                var child = Self.childOffset(bytes, parent: parent)
                while child != 0 && result.count < limit {
                    guard child + Self.nodeSize <= rawCount, pathCount < path.count else { return }
                    pathBase[pathCount] = bytes[child]
                    pathCount += 1
                    if bytes[child + 1] & Self.terminal != 0,
                       let word = String(bytes: UnsafeBufferPointer(start: pathBase, count: pathCount), encoding: .utf8) {
                        result.append(word)
                    }
                    visit(child)
                    pathCount -= 1
                    child = bytes[child + 1] & Self.hasSibling == 0 ? 0 : child + Self.nodeSize
                }
            }
            if result.count >= limit { return result }
            if pathCount == 0 {
                visit(0)
            } else if Self.readUInt32(bytes, at: node + 2) != 0 {
                visit(node)
            }
            return result
        }
    }

    @inline(__always)
    public func rootNode() -> Int { 0 }

    @inline(__always)
    public func isTerminal(node: Int) -> Bool {
        guard node >= 0, node + 1 < mapped.count else { return false }
        return mapped.base[node + 1] & Self.terminal != 0
    }

    @inline(__always)
    public func childNode(of parent: Int, byte: UInt8) -> Int? {
        guard parent >= 0 else { return nil }
        let bytes = mapped.base
        var child = Self.childOffset(bytes, parent: parent)
        while child != 0 {
            guard child + Self.nodeSize <= mapped.count else { return nil }
            let current = bytes[child]
            if current == byte { return child }
            if current > byte { break }
            child = (bytes[child + 1] & Self.hasSibling == 0) ? 0 : child + Self.nodeSize
        }
        return nil
    }

    /// Walks one UTF-8 key. Each sibling step checks cancellation so a stale
    /// touch frame aborts inside the trie instead of finishing the edge.
    @inline(__always)
    public func transition(from parent: Int, utf8: (UInt8, UInt8, UInt8, UInt8), length: UInt8) throws -> (node: Int, isTerminal: Bool)? {
        guard length > 0, parent >= 0 else { return nil }
        let bytes = mapped.base
        let rawCount = mapped.count
        var currentParent = parent
        var currentIsTerminal = false

        for i in 0..<Int(length) {
            try Task.checkCancellation()
            let targetByte: UInt8
            switch i {
            case 0: targetByte = utf8.0
            case 1: targetByte = utf8.1
            case 2: targetByte = utf8.2
            default: targetByte = utf8.3
            }

            var child = Self.childOffset(bytes, parent: currentParent)
            var found = 0
            while child != 0 {
                try Task.checkCancellation()
                guard child + Self.nodeSize <= rawCount else { return nil }
                let b = bytes[child]
                if b == targetByte {
                    found = child
                    break
                }
                if b > targetByte { break }
                child = (bytes[child + 1] & Self.hasSibling == 0) ? 0 : child + Self.nodeSize
            }
            guard found != 0 else { return nil }
            currentParent = found
            currentIsTerminal = (bytes[found + 1] & Self.terminal != 0)
        }
        return (currentParent, currentIsTerminal)
    }

    @inline(__always)
    public func forEachChild(of parent: Int, _ body: (UInt8, Int, Bool) -> Void) {
        guard parent >= 0 else { return }
        let bytes = mapped.base
        var child = Self.childOffset(bytes, parent: parent)
        while child != 0 {
            guard child + Self.nodeSize <= mapped.count else { return }
            let byte = bytes[child]
            let isTerm = (bytes[child + 1] & Self.terminal != 0)
            body(byte, child, isTerm)
            child = (bytes[child + 1] & Self.hasSibling == 0) ? 0 : child + Self.nodeSize
        }
    }

    private static func childOffset(_ bytes: UnsafePointer<UInt8>, parent: Int) -> Int {
        Int(readUInt32(bytes, at: parent + 2))
    }
    private static func readUInt32(_ bytes: UnsafePointer<UInt8>, at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }
    private static func validOffset(_ offset: UInt32, count: Int) -> Bool {
        offset >= UInt32(nodeSize) && Int(offset) < count && offset % UInt32(nodeSize) == 0
    }
}
