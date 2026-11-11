import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// An actual model can implement this interface later. Context is transient;
/// recognition never writes text or revises an already committed character.
public protocol CharacterLanguagePrior {
    func probability(of character: String, language: KeyboardLanguage, context: String) -> Double
}

public struct TouchRecognitionConfiguration {
    public var sigmaX: Double = 0.34
    public var sigmaY: Double = 0.32
    /// Offset is in key-pitch units, independent of cap sizes and screen scale.
    public var offsetX: Double = 0
    public var offsetY: Double = 0
    public var languageWeight: Double = 0
    public init() {}
}

public struct TouchCandidate {
    public let keyIndex: Int
    public let geometricProbability: Double
    public let languageProbability: Double
    public let probability: Double
}
public struct TouchResolution {
    public let first: TouchCandidate
    public let second: TouchCandidate?
    public let third: TouchCandidate?
    public var isAmbiguous: Bool { first.probability < 0.72 }
}

/// O(number of keys), fixed top-three storage, no candidate arrays/sorts on the
/// touch path. Function-key cells stay protected from character probabilities.
public struct TouchRecognizer {
    public let geometry: KeyboardGeometry
    public var configuration: TouchRecognitionConfiguration
    public init(geometry: KeyboardGeometry, configuration: TouchRecognitionConfiguration = .init()) {
        self.geometry = geometry; self.configuration = configuration
    }
    private struct Score {
        var index: Int = -1
        var geometric: Double = 0
        var language: Double = 1
        var combined: Double = -1
    }
    private var safeSigmaX: Double { configuration.sigmaX.isFinite ? min(0.6, max(0.15, configuration.sigmaX)) : 0.34 }
    private var safeSigmaY: Double { configuration.sigmaY.isFinite ? min(0.6, max(0.15, configuration.sigmaY)) : 0.32 }
    public var effectiveOffset: CGPoint {
        CGPoint(x: configuration.offsetX.isFinite ? min(0.2, max(-0.2, configuration.offsetX)) : 0,
                y: configuration.offsetY.isFinite ? min(0.2, max(-0.2, configuration.offsetY)) : 0)
    }
    public func resolve(_ point: CGPoint, prior: (any CharacterLanguagePrior)? = nil, context: String = "") -> TouchResolution? {
        guard let cell = geometry.cellIndex(at: point) else { return nil }
        if geometry.keys[cell].role.character == nil {
            return TouchResolution(first: TouchCandidate(keyIndex: cell, geometricProbability: 1, languageProbability: 1, probability: 1), second: nil, third: nil)
        }
        let offset = effectiveOffset
        let x = Double(point.x) / Double(geometry.pitch.width) - Double(offset.x)
        let y = Double(point.y) / Double(geometry.pitch.height) - Double(offset.y)
        let sx = safeSigmaX, sy = safeSigmaY
        let weight = configuration.languageWeight.isFinite ? min(0.35, max(0, configuration.languageWeight)) : 0
        let selectedIsNumberRow = geometry.hasNumberRow && geometry.keys[cell].row == 0
        var first = Score(), second = Score(), third = Score(), geometricTotal = 0.0, total = 0.0
        for key in geometry.keys {
            guard let character = key.role.character else { continue }
            if geometry.hasNumberRow && ((key.row == 0) != selectedIsNumberRow) { continue }
            let dx = (x - Double(key.center.x / geometry.pitch.width)) / sx
            let dy = (y - Double(key.center.y / geometry.pitch.height)) / sy
            let distance = dx * dx + dy * dy
            // Distant characters cannot win on a linguistic prior alone.
            guard distance < 100 else { continue }
            let geometric = exp(-0.5 * distance)
            let raw = weight > 0 ? prior?.probability(of: character, language: geometry.language, context: context) ?? 1 : 1
            let language = raw.isFinite ? min(1, max(0.001, raw)) : 1
            let combined = geometric * (weight > 0 ? pow(language, weight) : 1)
            let value = Score(index: key.index, geometric: geometric, language: language, combined: combined)
            geometricTotal += geometric; total += combined
            // Stable key-index tie break: iteration order is layout order.
            if combined > first.combined + 1e-14 { third = second; second = first; first = value }
            else if combined > second.combined + 1e-14 { third = second; second = value }
            else if combined > third.combined + 1e-14 { third = value }
        }
        guard first.index >= 0, total > 0, geometricTotal > 0 else { return nil }
        func candidate(_ value: Score) -> TouchCandidate? {
            guard value.index >= 0 else { return nil }
            return TouchCandidate(keyIndex: value.index, geometricProbability: value.geometric / geometricTotal,
                                  languageProbability: value.language, probability: value.combined / total)
        }
        return TouchResolution(first: candidate(first)!, second: candidate(second), third: candidate(third))
    }

    /// Exact clipped Gaussian/Voronoi regions for the default geometry-only
    /// resolver. Built only when debug display/layout/calibration changes.
    public func debugZones() -> [TouchDebugZone] {
        guard !geometry.keys.isEmpty else { return [] }
        let offset = effectiveOffset
        let scaleX = Double(geometry.pitch.width) * safeSigmaX
        let scaleY = Double(geometry.pitch.height) * safeSigmaY
        func center(_ key: KeyboardKeyGeometry) -> CGPoint {
            CGPoint(x: key.center.x + offset.x * geometry.pitch.width, y: key.center.y + offset.y * geometry.pitch.height)
        }
        func rectangle(_ rect: CGRect) -> [CGPoint] {
            [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
             CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        }
        func clip(_ polygon: [CGPoint], a: Double, b: Double, c: Double) -> [CGPoint] {
            guard let last = polygon.last else { return [] }
            var result: [CGPoint] = [], previous = last
            var previousValue = a * Double(last.x) + b * Double(last.y) - c
            for point in polygon {
                let value = a * Double(point.x) + b * Double(point.y) - c
                if (value <= 0) != (previousValue <= 0) {
                    let t = previousValue / (previousValue - value)
                    result.append(CGPoint(x: Double(previous.x) + t * Double(point.x - previous.x),
                                          y: Double(previous.y) + t * Double(point.y - previous.y)))
                }
                if value <= 0 { result.append(point) }
                previous = point; previousValue = value
            }
            return result
        }
        var zones: [TouchDebugZone] = []
        for key in geometry.keys {
            guard key.role.character != nil else { zones.append(TouchDebugZone(keyIndex: key.index, polygon: rectangle(key.touchFrame))); continue }
            var polygon = rectangle(geometry.bounds)
            let p = center(key)
            for other in geometry.keys where other.index != key.index && other.role.character != nil {
                if geometry.hasNumberRow && ((key.row == 0) != (other.row == 0)) { continue }
                let q = center(other)
                let a = 2 * Double(q.x - p.x) / (scaleX * scaleX)
                let b = 2 * Double(q.y - p.y) / (scaleY * scaleY)
                let c = (Double(q.x * q.x - p.x * p.x) / (scaleX * scaleX)) + (Double(q.y * q.y - p.y * p.y) / (scaleY * scaleY))
                polygon = clip(polygon, a: a, b: b, c: c)
                if polygon.isEmpty { break }
            }
            for cell in geometry.keys where cell.role.character != nil {
                if geometry.hasNumberRow && ((key.row == 0) != (cell.row == 0)) { continue }
                var part = clip(polygon, a: -1, b: 0, c: -Double(cell.touchFrame.minX))
                part = clip(part, a: 1, b: 0, c: Double(cell.touchFrame.maxX))
                part = clip(part, a: 0, b: -1, c: -Double(cell.touchFrame.minY))
                part = clip(part, a: 0, b: 1, c: Double(cell.touchFrame.maxY))
                if part.count >= 3 { zones.append(TouchDebugZone(keyIndex: key.index, polygon: part)) }
            }
        }
        return zones
    }
}
public struct TouchDebugZone { public let keyIndex: Int; public let polygon: [CGPoint] }
