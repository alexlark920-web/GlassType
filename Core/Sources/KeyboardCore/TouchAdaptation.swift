import Foundation

/// Numeric aggregates only: no key IDs, letters, timestamps, raw touch histories,
/// surrounding text or document identifiers can be encoded by this type.
public struct TouchOffsetStatistics: Codable, Equatable {
    public private(set) var count = 0
    public private(set) var meanX = 0.0
    public private(set) var meanY = 0.0
    public private(set) var varianceSumX = 0.0
    public private(set) var varianceSumY = 0.0
    public init() {}

    @discardableResult public mutating func observe(x: Double, y: Double) -> Bool {
        guard x.isFinite, y.isFinite, abs(x) <= 0.42, abs(y) <= 0.42 else { return false }
        let dx = x - meanX, dy = y - meanY
        count = min(4096, count + 1)
        let rate = 1 / Double(count)
        meanX += dx * rate; meanY += dy * rate
        if count < 4096 {
            varianceSumX += dx * (x - meanX); varianceSumY += dy * (y - meanY)
        } else {
            varianceSumX = (1 - rate) * varianceSumX + dx * (x - meanX)
            varianceSumY = (1 - rate) * varianceSumY + dy * (y - meanY)
        }
        return true
    }
    public var offsetX: Double { trustedOffset(meanX, varianceSum: varianceSumX) }
    public var offsetY: Double { trustedOffset(meanY, varianceSum: varianceSumY) }
    private func trustedOffset(_ mean: Double, varianceSum: Double) -> Double {
        guard isValid, count >= 32 else { return 0 }
        // Ramp in slowly; noisy/ambiguous observations have little influence.
        let variance = varianceSum / Double(max(1, count - 1))
        let reliability = min(1, max(0, (0.09 - variance) / 0.06))
        let ramp = min(1, Double(count - 31) / 96)
        return min(0.18, max(-0.18, mean)) * ramp * reliability
    }
    public var isValid: Bool {
        (0...4096).contains(count) && meanX.isFinite && meanY.isFinite && abs(meanX) <= 0.42 && abs(meanY) <= 0.42 &&
        varianceSumX.isFinite && varianceSumY.isFinite && varianceSumX >= 0 && varianceSumY >= 0 &&
        varianceSumX <= 4096 && varianceSumY <= 4096
    }
}
public struct TouchAdaptationState: Codable, Equatable {
    public private(set) var version = 1
    public var portrait = TouchOffsetStatistics()
    public var landscape = TouchOffsetStatistics()
    public init() {}
    public var isValid: Bool { version == 1 && portrait.isValid && landscape.isValid }
    public func configuration(landscape: Bool, enabled: Bool) -> TouchRecognitionConfiguration {
        var result = TouchRecognitionConfiguration()
        if enabled && isValid {
            let stats = landscape ? self.landscape : portrait
            result.offsetX = stats.offsetX; result.offsetY = stats.offsetY
        }
        return result
    }
}
