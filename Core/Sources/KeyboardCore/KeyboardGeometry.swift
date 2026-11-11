import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum KeyboardKeyRole: Equatable {
    case character(String), shift, backspace, modeSwitch, language, systemKeyboard, space, enter
    public var character: String? { if case let .character(value) = self { return value }; return nil }
}

/// User-adjustable sizing stays inside ranges that keep the key grid inside
/// the extension's self-sizing surface. Width changes affect the visible
/// caps only; every key keeps its original non-overlapping touch slot.
public enum KeyboardSizing {
    public static func heightScale(_ value: Double) -> Double {
        value.isFinite ? min(1.10, max(0.92, value)) : 1
    }
    public static func visualWidthScale(_ value: Double) -> Double {
        value.isFinite ? min(1.12, max(0.84, value)) : 1
    }
    public static func height(base: CGFloat, scale: Double, hasToolbar: Bool, bottomInset: CGFloat) -> CGFloat {
        max(132, base * heightScale(scale) - (hasToolbar ? 0 : 32) + max(0, bottomInset))
    }
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
    public let hasNumberRow: Bool

    public static func make(bounds: CGRect, language: KeyboardLanguage,
                            symbolPage: SymbolPage? = nil, compact: Bool = true,
                            needsSystemKey: Bool = false, customRows: [[String]]? = nil,
                            numberRow: Bool = false,
                            thirdRowUsesModeSwitch: Bool = false,
                            visualWidthScale: CGFloat = 1) -> KeyboardGeometry {
        guard [bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height].allSatisfy({ $0.isFinite }),
              bounds.width >= 80, bounds.height >= 80 else {
            return KeyboardGeometry(bounds: .zero, language: language, keys: [], pitch: .zero, hasNumberRow: false)
        }
        let rows = customRows ?? symbolPage?.rows ?? language.rows
        let showsNumberRow = numberRow && symbolPage == nil && customRows == nil
        guard rows.count == 3, rows.allSatisfy({ !$0.isEmpty }) else {
            return KeyboardGeometry(bounds: .zero, language: language, keys: [], pitch: .zero, hasNumberRow: false)
        }
        let columns = max(showsNumberRow ? 10 : 0, max(rows[0].count, max(rows[1].count, rows[2].count + 2)))
        let rowCount = 4 + (showsNumberRow ? 1 : 0)
        let margin: CGFloat = 4, bottomMargin: CGFloat = 5
        let contentWidth = bounds.width - margin * 2
        let height = (bounds.height - bottomMargin) / CGFloat(rowCount)
        var result: [KeyboardKeyGeometry] = []
        result.reserveCapacity(rows.reduce(0) { $0 + $1.count } + 9 + (showsNumberRow ? 10 : 0))
        func appendRow(_ roles: [KeyboardKeyRole], weights: [CGFloat], row: Int) {
            let total = weights.reduce(0, +)
            let scale = contentWidth / total
            var x = bounds.minX + margin
            for position in roles.indices {
                let end = position == roles.count - 1 ? bounds.maxX - margin : x + weights[position] * scale
                let slot = CGRect(x: x, y: bounds.minY + CGFloat(row) * height, width: end - x, height: height)
                let h: CGFloat = compact ? min(3.4, max(2.2, slot.width * 0.09)) : 3
                let v: CGFloat = compact ? (height >= 42 ? 5 : 3.5) : 3.5
                let touchLeft = position == 0 ? bounds.minX : x
                let touchRight = position == roles.count - 1 ? bounds.maxX : end
                let safeScale = CGFloat(KeyboardSizing.visualWidthScale(Double(visualWidthScale)))
                let baseVisual = slot.insetBy(dx: min(h, slot.width * 0.2), dy: min(v, height * 0.2))
                let visualWidth = min(max(0, slot.width - 4.4), max(0, baseVisual.width * safeScale))
                let visual = CGRect(x: slot.midX - visualWidth / 2, y: baseVisual.minY,
                                    width: visualWidth, height: baseVisual.height)
                result.append(KeyboardKeyGeometry(index: result.count, row: row, role: roles[position], slotFrame: slot,
                    visualFrame: visual,
                    touchFrame: CGRect(x: touchLeft, y: slot.minY, width: touchRight - touchLeft,
                                       height: height + (row == rowCount - 1 ? bottomMargin : 0))))
                x = end
            }
        }
        let rowOffset = showsNumberRow ? 1 : 0
        if showsNumberRow {
            appendRow(Array("1234567890").map { String($0) },
                      weights: Array(repeating: 1, count: 10), row: 0)
        }
        for row in 0..<3 {
            let characters = rows[row].map(KeyboardKeyRole.character)
            if row == 2 {
                let functionWeight = CGFloat(columns - rows[row].count) / 2
                appendRow([thirdRowUsesModeSwitch ? .modeSwitch : .shift] + characters + [.backspace],
                          weights: [functionWeight] + Array(repeating: 1, count: characters.count) + [functionWeight],
                          row: row + rowOffset)
            } else {
                // Each alphabet row fills the same horizontal span. Layouts
                // with fewer keys distribute the extra width across those keys.
                appendRow(characters, weights: Array(repeating: 1, count: characters.count), row: row + rowOffset)
            }
        }
        var bottom: [KeyboardKeyRole] = [.modeSwitch, .language]
        var weights: [CGFloat] = [1, 0.85]
        if needsSystemKey { bottom.append(.systemKeyboard); weights.append(0.85) }
        bottom += [.character(","), .space, .character("."), .enter]
        weights += [0.85, 3.6, 0.85, 1.35]
        appendRow(bottom, weights: weights, row: 3 + rowOffset)
        return KeyboardGeometry(bounds: bounds, language: language, keys: result,
                                pitch: CGSize(width: contentWidth / CGFloat(columns), height: height),
                                hasNumberRow: showsNumberRow)
    }

    /// Half-open cells have one owner, including exact shared edges. The outer
    /// right/bottom edge belongs to the last cell; points outside stay outside.
    public func cellIndex(at point: CGPoint) -> Int? {
        guard point.x.isFinite, point.y.isFinite, point.x >= bounds.minX, point.x <= bounds.maxX,
              point.y >= bounds.minY, point.y <= bounds.maxY, !keys.isEmpty else { return nil }
        guard let row = keys.last(where: { point.y >= $0.slotFrame.minY })?.row else { return nil }
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
