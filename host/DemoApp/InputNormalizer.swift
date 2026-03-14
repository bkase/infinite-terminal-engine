import AppKit
import CoreGraphics

enum InputNormalizer {
    static func panDelta(from start: CGPoint, to end: CGPoint) -> CGSize {
        CGSize(width: end.x - start.x, height: end.y - start.y)
    }

    static func zoomFactor(forMagnification magnification: CGFloat) -> Float {
        Float(max(0.25, min(4, 1 + magnification)))
    }

    static func fallbackZoomFactor(forScrollDeltaY deltaY: CGFloat) -> Float {
        let step = deltaY / 240
        let unclamped = pow(1.25, -step)
        return Float(max(0.25, min(4, unclamped)))
    }
}
