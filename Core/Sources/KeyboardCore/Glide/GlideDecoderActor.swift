import CoreGraphics
import Foundation

/// Serializes glide decoding away from the keyboard UI executor.
public actor GlideDecoderActor {
    private let decoder = GlideDecoder()

    public init() {}

    public func decode(points: [CGPoint], keyCenters: [String: CGPoint],
                       language: KeyboardLanguage, extraWords: [String] = [],
                       limit: Int = 3) async throws -> [String] {
        try Task.checkCancellation()
        // Give a newly submitted gesture a chance to cancel a queued request
        // before entering the synchronous scoring loops.
        await Task.yield()
        try Task.checkCancellation()
        let result = decoder.decode(points: points, keyCenters: keyCenters,
                                    language: language, extraWords: extraWords,
                                    limit: limit, isCancelled: { Task.isCancelled })
        try Task.checkCancellation()
        return result
    }
}
