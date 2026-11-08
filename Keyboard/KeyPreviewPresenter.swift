import UIKit
import KeyboardCore

/// Reuses a small layer pool for key previews. Updating the popup changes only
/// layer geometry and text; it never inserts views or triggers Auto Layout.
@MainActor
final class KeyPreviewPresenter {
    private let container = CALayer()
    private let bubble = CAShapeLayer()
    private let glyph = CATextLayer()
    private let symbol = CALayer()
    private var attached = false
    private(set) var isVisible = false

    init() {
        container.masksToBounds = false
        container.zPosition = 100
        container.shadowColor = UIColor.black.cgColor
        container.shadowOpacity = 0.20
        container.shadowRadius = 3
        container.shadowOffset = CGSize(width: 0, height: 2)
        bubble.fillColor = UIColor.secondarySystemBackground.cgColor
        bubble.contentsScale = UIScreen.main.scale
        glyph.alignmentMode = .center
        glyph.contentsScale = UIScreen.main.scale
        glyph.truncationMode = .middle
        symbol.contentsGravity = .resizeAspect
        container.addSublayer(bubble)
        container.addSublayer(glyph)
        container.addSublayer(symbol)
        container.isHidden = true
    }

    func attach(to layer: CALayer) {
        guard !attached else { return }
        attached = true
        layer.addSublayer(container)
    }

    func show(layout: KeyPreviewLayout, text: String, fill: UIColor, ink: UIColor) {
        configure(layout: layout, fill: fill, ink: ink)
        glyph.string = text
        glyph.font = UIFont.systemFont(ofSize: min(34, max(25, layout.frame.height - 22)), weight: .regular)
        glyph.fontSize = min(34, max(25, layout.frame.height - 22))
        glyph.foregroundColor = ink.cgColor
        symbol.contents = nil
        symbol.isHidden = true
        reveal()
    }

    func showSymbol(layout: KeyPreviewLayout, name: String, fill: UIColor, ink: UIColor) {
        configure(layout: layout, fill: fill, ink: ink)
        glyph.string = nil
        symbol.contents = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .medium))?
            .withTintColor(ink, renderingMode: .alwaysOriginal).cgImage
        symbol.isHidden = symbol.contents == nil
        reveal()
    }

    func hide() {
        isVisible = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.isHidden = true
        container.opacity = 0
        CATransaction.commit()
    }

    private func configure(layout: KeyPreviewLayout, fill: UIColor, ink: UIColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.frame = layout.frame
        let bubblePath = path(size: layout.frame.size, stemCenterX: layout.stemCenterX,
                              stemWidth: layout.stemWidth).cgPath
        container.shadowPath = bubblePath
        bubble.frame = CGRect(origin: .zero, size: layout.frame.size)
        bubble.path = bubblePath
        bubble.fillColor = fill.resolvedColor(with: UITraitCollection.current).cgColor
        glyph.frame = CGRect(x: 4, y: 0, width: max(0, layout.frame.width - 8),
                             height: max(0, layout.frame.height - 12))
        symbol.frame = CGRect(x: (layout.frame.width - 28) / 2,
                              y: max(0, (layout.frame.height - 40) / 2), width: 28, height: 28)
        glyph.foregroundColor = ink.cgColor
        CATransaction.commit()
    }

    private func reveal() {
        isVisible = true
        container.isHidden = false
        container.removeAllAnimations()
        container.opacity = 1
        container.transform = CATransform3DIdentity
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.35
        fade.toValue = 1
        fade.duration = 0.07
        container.add(fade, forKey: "preview.fade")
    }

    private func path(size: CGSize, stemCenterX: CGFloat, stemWidth: CGFloat) -> UIBezierPath {
        let bubbleHeight = max(1, size.height - 12)
        let radius = min(10, bubbleHeight / 3)
        let left = stemCenterX - stemWidth / 2
        let right = stemCenterX + stemWidth / 2
        let width = size.width
        let path = UIBezierPath()
        path.move(to: CGPoint(x: radius, y: 0))
        path.addLine(to: CGPoint(x: width - radius, y: 0))
        path.addQuadCurve(to: CGPoint(x: width, y: radius), controlPoint: CGPoint(x: width, y: 0))
        path.addLine(to: CGPoint(x: width, y: bubbleHeight - radius))
        path.addQuadCurve(to: CGPoint(x: width - radius, y: bubbleHeight), controlPoint: CGPoint(x: width, y: bubbleHeight))
        path.addLine(to: CGPoint(x: min(width - radius, right + 4), y: bubbleHeight))
        path.addQuadCurve(to: CGPoint(x: right, y: bubbleHeight + 4), controlPoint: CGPoint(x: right, y: bubbleHeight))
        path.addLine(to: CGPoint(x: right, y: size.height - 3))
        path.addQuadCurve(to: CGPoint(x: right - 3, y: size.height), controlPoint: CGPoint(x: right, y: size.height))
        path.addLine(to: CGPoint(x: left + 3, y: size.height))
        path.addQuadCurve(to: CGPoint(x: left, y: size.height - 3), controlPoint: CGPoint(x: left, y: size.height))
        path.addLine(to: CGPoint(x: left, y: bubbleHeight + 4))
        path.addQuadCurve(to: CGPoint(x: max(radius, left - 4), y: bubbleHeight), controlPoint: CGPoint(x: left, y: bubbleHeight))
        path.addLine(to: CGPoint(x: radius, y: bubbleHeight))
        path.addQuadCurve(to: CGPoint(x: 0, y: bubbleHeight - radius), controlPoint: CGPoint(x: 0, y: bubbleHeight))
        path.addLine(to: CGPoint(x: 0, y: radius))
        path.addQuadCurve(to: CGPoint(x: radius, y: 0), controlPoint: CGPoint(x: 0, y: 0))
        path.close()
        return path
    }
}
