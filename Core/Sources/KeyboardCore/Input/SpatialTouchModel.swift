import Foundation
import CoreGraphics
import simd

/// Spatial touch model evaluating Gaussian probability distributions over keyboard key centers.
/// Operates strictly on SIMD2<Float> and primitive Floats with zero heap allocations in the hot path.
public struct SpatialTouchModel: Sendable {
    public static let defaultSigma: Float = 34.0
    public static let maximumKeyCount: Int = 64

    public struct KeyLocation: Sendable, Equatable {
        public let key: String
        public let center: SIMD2<Float>
        public let utf8Bytes: (UInt8, UInt8, UInt8, UInt8)
        public let utf8Length: UInt8

        public init(key: String, center: SIMD2<Float>) {
            self.key = key
            self.center = center
            var b: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
            var len: UInt8 = 0
            for byte in key.utf8.prefix(4) {
                switch len {
                case 0: b.0 = byte
                case 1: b.1 = byte
                case 2: b.2 = byte
                default: b.3 = byte
                }
                len += 1
            }
            self.utf8Bytes = b
            self.utf8Length = len
        }

        public init(key: String, centerPoint: CGPoint) {
            self.init(key: key, center: SIMD2<Float>(Float(centerPoint.x), Float(centerPoint.y)))
        }
    }

    /// Fixed-size candidate slot for zero-allocation candidate gathering.
    public struct ScoredKey: Sendable, Equatable {
        public var keyIndex: Int16
        public var probability: Float
        public var logProbability: Float

        public init(keyIndex: Int16 = -1, probability: Float = 0, logProbability: Float = -.infinity) {
            self.keyIndex = keyIndex
            self.probability = probability
            self.logProbability = logProbability
        }
    }

    public let keys: [KeyLocation]
    public let sigma: Float
    public let twoSigmaSquared: Float
    public let invTwoSigmaSquared: Float

    public init(keys: [KeyLocation] = [], sigma: Float = defaultSigma) {
        self.keys = keys
        let s = max(1.0, sigma)
        self.sigma = s
        let twoSS = 2.0 * s * s
        self.twoSigmaSquared = twoSS
        self.invTwoSigmaSquared = 1.0 / twoSS
    }

    public init(keyCenters: [String: CGPoint], sigma: Float = defaultSigma) {
        let sortedKeys = keyCenters.keys.sorted()
        let locations = sortedKeys.compactMap { key -> KeyLocation? in
            guard let pt = keyCenters[key] else { return nil }
            return KeyLocation(key: key, centerPoint: pt)
        }
        self.init(keys: locations, sigma: sigma)
    }

    public init(geometry: KeyboardGeometry, sigma: Float = defaultSigma) {
        var locations: [KeyLocation] = []
        for key in geometry.keys {
            if let character = key.role.character, character.allSatisfy(\.isLetter) {
                locations.append(KeyLocation(key: character, centerPoint: key.center))
            }
        }
        self.init(keys: locations, sigma: sigma)
    }

    /// P_spatial(touch, key) = exp(- (dist(touch, key_center)^2) / (2 * sigma^2))
    /// Pure SIMD2<Float> calculation with zero heap allocations.
    @inline(__always)
    public func spatialProbability(touch: SIMD2<Float>, keyCenter: SIMD2<Float>) -> Float {
        let delta = touch - keyCenter
        let distSq = delta.x * delta.x + delta.y * delta.y
        return exp(-distSq * invTwoSigmaSquared)
    }

    /// Direct log-probability: -distSq / (2 * sigma^2).
    /// Avoids exp() followed by log() for maximum speed and precision.
    @inline(__always)
    public func spatialLogProbability(touch: SIMD2<Float>, keyCenter: SIMD2<Float>) -> Float {
        let delta = touch - keyCenter
        let distSq = delta.x * delta.x + delta.y * delta.y
        return -distSq * invTwoSigmaSquared
    }

    /// Zero-allocation nearest key candidate gathering into a preallocated mutable buffer.
    /// Returns the number of candidates placed into the buffer (sorted descending by probability).
    @inline(__always)
    public func evaluate(
        touch: SIMD2<Float>,
        into buffer: UnsafeMutableBufferPointer<ScoredKey>,
        probabilityThreshold: Float = 0.001
    ) -> Int {
        let maxCount = buffer.count
        guard maxCount > 0 else { return 0 }
        var count = 0

        for i in 0..<keys.count {
            let keyCenter = keys[i].center
            let delta = touch - keyCenter
            let distSq = delta.x * delta.x + delta.y * delta.y
            let logP = -distSq * invTwoSigmaSquared
            let p = exp(logP)

            if p >= probabilityThreshold {
                if count < maxCount {
                    buffer[count] = ScoredKey(keyIndex: Int16(i), probability: p, logProbability: logP)
                    count += 1
                    var j = count - 1
                    while j > 0 && buffer[j].probability > buffer[j - 1].probability {
                        let tmp = buffer[j]
                        buffer[j] = buffer[j - 1]
                        buffer[j - 1] = tmp
                        j -= 1
                    }
                } else if p > buffer[maxCount - 1].probability {
                    buffer[maxCount - 1] = ScoredKey(keyIndex: Int16(i), probability: p, logProbability: logP)
                    var j = maxCount - 1
                    while j > 0 && buffer[j].probability > buffer[j - 1].probability {
                        let tmp = buffer[j]
                        buffer[j] = buffer[j - 1]
                        buffer[j - 1] = tmp
                        j -= 1
                    }
                }
            }
        }
        return count
    }

    /// Convenience candidate evaluation returning high-level results.
    public func topCandidates(for touch: CGPoint, limit: Int = 4, threshold: Float = 0.001) -> [(key: KeyLocation, probability: Float, logProbability: Float)] {
        guard limit > 0, !keys.isEmpty else { return [] }
        let touchSIMD = SIMD2<Float>(Float(touch.x), Float(touch.y))
        var raw = [ScoredKey](repeating: ScoredKey(), count: min(limit, keys.count))
        let placed = raw.withUnsafeMutableBufferPointer { buffer in
            evaluate(touch: touchSIMD, into: buffer, probabilityThreshold: threshold)
        }
        var result: [(key: KeyLocation, probability: Float, logProbability: Float)] = []
        result.reserveCapacity(placed)
        for i in 0..<placed {
            let idx = Int(raw[i].keyIndex)
            if keys.indices.contains(idx) {
                result.append((key: keys[idx], probability: raw[i].probability, logProbability: raw[i].logProbability))
            }
        }
        return result
    }
}
