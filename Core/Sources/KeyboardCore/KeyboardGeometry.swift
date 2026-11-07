import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum KeyboardKeyRole: Equatable {
    case character(String), shift, backspace, modeSwitch, language, systemKeyboard, space, enter
    public var character: String? { if case let .character(value) = self { return value }; return nil }
}

/// Immutable layout shared by UIKit, tap recognition, previews and glide input.
/// `slotFrame` positions a view; `visualFrame` draws its cap; `touchFrame` fills
/// gaps/row margins. None of these depends on the learned touch offset.
public struct KeyboardKeyGeometry {
    public let index: Int
    public let row: Int
    public let role: KeyboardKeyRole
    public let slotFrame: CGRect
    public let visualFrame: CGRect
    public let touchFrame: CGRect
    public var center: CGPoint { CGPoint(x: slotFrame.midX, y: slotFrame.midY) }
}

public struct KeyboardGeometry {
    public let bounds: CGRect
    public let language: KeyboardLanguage
    public let keys: [KeyboardKeyGeometry]
    public let pitch: CGSize

    public static func make(bounds: CGRect, language: KeyboardLanguage,
                            symbolPage: SymbolPage? = nil, compact: Bool = true,
                            needsSystemKey: Bool = false) -> KeyboardGeometry {
        guard [bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height].allSatisfy({ $0.isFinite }),
              bounds.width >= 80, bounds.height >= 80 else {
            return KeyboardGeometry(bounds: .zero, language: language, keys: [], pitch: .zero)
        }
        let rows = symbolPage?.rows ?? language.rows
        let columns = max(rows[0].count, max(rows[1].count, rows[2].count + 2))
        let margin: CGFloat = 4, bottomMargin: CGFloat = 5
        let contentWidth = bounds.width - margin * 2
        let unit = contentWidth / CGFloat(columns), height = (bounds.height - bottomMargin) / 4
        var result: [KeyboardKeyGeometry] = []
        result.reserveCapacity(rows.reduce(0) { $0 + $1.count } + 9)
        func appendRow(_ roles: [KeyboardKeyRole], weights: [CGFloat], row: Int, inset: CGFloat = 0) {
            let total = weights.reduce(0, +)
            let scale = (contentWidth - inset * 2) / total
            var x = bounds.minX + margin + inset
            for position in roles.indices {
                let end = position == roles.count - 1 ? bounds.maxX - margin - inset : x + weights[position] * scale
                let slot = CGRect(x: x, y: bounds.minY + CGFloat(row) * height, width: end - x, height: height)
                let h: CGFloat = compact ? min(3.4, max(2.2, slot.width * 0.09)) : 3
                let v: CGFloat = compact ? (height >= 42 ? 5 : 3.5) : 3.5
                let touchLeft = position == 0 ? bounds.minX : x
                let touchRight = position == roles.count - 1 ? bounds.maxX : end
                result.append(KeyboardKeyGeometry(index: result.count, row: row, role: roles[position], slotFrame: slot,
                    visualFrame: slot.insetBy(dx: min(h, slot.width * 0.2), dy: min(v, height * 0.2)),
                    touchFrame: CGRect(x: touchLeft, y: slot.minY, width: touchRight - touchLeft, height: height + (row == 3 ? bottomMargin : 0))))
                x = end
            }
        }
        for row in 0..<3 {
            let characters = rows[row].map(KeyboardKeyRole.character)
            if row == 2 {
                let functionWeight = CGFloat(columns - rows[row].count) / 2
                appendRow([.shift] + characters + [.backspace],
                          weights: [functionWeight] + Array(repeating: 1, count: characters.count) + [functionWeight], row: row)
            } else {
                // EN's second row is offset by half a pitch; Cyrillic layouts
                // get the matching half-pitch when their row is one key shorter.
                let inset = (contentWidth - CGFloat(characters.count) * unit) / 2
                appendRow(characters, weights: Array(repeating: 1, count: characters.count), row: row, inset: inset)
            }
        }
        var bottom: [KeyboardKeyRole] = [.modeSwitch, .language]
        var weights: [CGFloat] = [1, 0.85]
        if needsSystemKey { bottom.append(.systemKeyboard); weights.append(0.85) }
        bottom += [.character(","), .space, .character("."), .enter]
        weights += [0.85, 3.6, 0.85, 1.35]
        appendRow(bottom, weights: weights, row: 3)
        return KeyboardGeometry(bounds: bounds, language: language, keys: result, pitch: CGSize(width: unit, height: height))
    }

    /// Half-open cells have one owner, including exact shared edges. The outer
    /// right/bottom edge belongs to the last cell; points outside stay outside.
    public func cellIndex(at point: CGPoint) -> Int? {
        guard point.x.isFinite, point.y.isFinite, point.x >= bounds.minX, point.x <= bounds.maxX,
              point.y >= bounds.minY, point.y <= bounds.maxY, !keys.isEmpty else { return nil }
        // Compare the same stored boundary expressions used by layout. Division
        // can turn an exact row edge into 2.9999999999999996 on fractional sizes.
        let row: Int
        if point.y < bounds.minY + pitch.height { row = 0 }
        else if point.y < bounds.minY + 2 * pitch.height { row = 1 }
        else if point.y < bounds.minY + 3 * pitch.height { row = 2 }
        else { row = 3 }
        for index in keys.indices where keys[index].row == row {
            let next = index + 1
            // The next cell's start is the canonical shared edge; reconstructing
            // it as origin + width can introduce a one-ULP gap or overlap.
            let right = next < keys.count && keys[next].row == row ? keys[next].touchFrame.minX : bounds.maxX
            if point.x < right || right == bounds.maxX { return index }
        }
        return nil
    }
}
