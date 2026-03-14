import AppKit
import MetalKit

@MainActor
protocol CanvasInputHandler: AnyObject {
    func canvasDidPan(delta: CGSize)
    func canvasDidZoom(factor: Float, anchor: CGPoint)
}

final class MetalCanvasView: MTKView {
    weak var inputHandler: CanvasInputHandler?

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            let point = convert(event.locationInWindow, from: nil)
            inputHandler?.canvasDidZoom(
                factor: InputNormalizer.fallbackZoomFactor(forScrollDeltaY: event.scrollingDeltaY),
                anchor: point
            )
        } else {
            inputHandler?.canvasDidPan(delta: InputNormalizer.panDelta(for: event))
        }
    }

    override func magnify(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        inputHandler?.canvasDidZoom(factor: InputNormalizer.zoomFactor(forMagnification: event.magnification), anchor: point)
    }
}
