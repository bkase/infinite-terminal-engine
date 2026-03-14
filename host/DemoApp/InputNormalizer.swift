import AppKit
import CoreGraphics

enum InputNormalizer {
    static func panDelta(for event: NSEvent) -> CGSize {
        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
        return CGSize(width: event.scrollingDeltaX * multiplier, height: event.scrollingDeltaY * multiplier)
    }

    static func zoomFactor(forMagnification magnification: CGFloat) -> Float {
        Float(max(0.25, min(4, 1 + magnification)))
    }

    static func fallbackZoomFactor(forScrollDeltaY deltaY: CGFloat) -> Float {
        deltaY < 0 ? 1.1 : 0.9
    }
}
