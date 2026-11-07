import Foundation
import CoreGraphics

/// Keeps the character flag inside the extension, including the first row and
/// the screen edges. The OS does not allow drawing above the keyboard window.
public struct KeyPreviewLayout {
    public let frame: CGRect
    public let stemCenterX: CGFloat
    public let stemWidth: CGFloat

    public static func make(keyFrame: CGRect, availableBounds: CGRect) -> KeyPreviewLayout? {
        let values: [CGFloat] = [keyFrame.minX, keyFrame.minY, keyFrame.width, keyFrame.height,
                      availableBounds.minX, availableBounds.minY, availableBounds.width, availableBounds.height]
        guard values.allSatisfy({ $0.isFinite }), keyFrame.width > 0, keyFrame.height > 0,
              availableBounds.width >= 44, availableBounds.height >= 56,
              availableBounds.intersects(keyFrame) else { return nil }
        let desiredWidth: CGFloat = max(52, keyFrame.width + 22)
        let width: CGFloat = min(62, min(desiredWidth, availableBounds.width - 8))
        let keyAnchorY: CGFloat = keyFrame.minY + min(18, keyFrame.height * 0.3)
        let minimumAnchorY: CGFloat = availableBounds.minY + 50
        let anchorY: CGFloat = min(availableBounds.maxY - 2, max(minimumAnchorY, keyAnchorY))
        let y: CGFloat = max(availableBounds.minY + 2, anchorY - 68)
        let desiredX: CGFloat = max(availableBounds.minX + 4, keyFrame.midX - width / 2)
        let x: CGFloat = min(desiredX, availableBounds.maxX - width - 4)
        let frame = CGRect(x: x, y: y, width: width, height: anchorY - y)
        let stemWidth: CGFloat = min(max(16, keyFrame.width - 8), width - 12)
        let minimumCenter: CGFloat = stemWidth / 2 + 2
        let maximumCenter: CGFloat = width - stemWidth / 2 - 2
        let center: CGFloat = min(max(minimumCenter, keyFrame.midX - x), maximumCenter)
        return KeyPreviewLayout(frame: frame, stemCenterX: center, stemWidth: stemWidth)
    }
}
