import AppKit
import MetalKit

@MainActor
protocol CanvasInputHandler: AnyObject {
    func canvasDidPan(delta: CGSize)
    func canvasDidZoom(factor: Float, anchor: CGPoint)
}

final class MetalCanvasView: MTKView {
    weak var inputHandler: CanvasInputHandler?
    private var dragStartPoint: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragStartPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        let currentPoint = convert(event.locationInWindow, from: nil)
        guard let dragStartPoint else {
            self.dragStartPoint = currentPoint
            return
        }
        inputHandler?.canvasDidPan(delta: InputNormalizer.panDelta(from: dragStartPoint, to: currentPoint))
        self.dragStartPoint = currentPoint
    }

    override func mouseUp(with event: NSEvent) {
        _ = event
        dragStartPoint = nil
    }

    override func scrollWheel(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        inputHandler?.canvasDidZoom(
            factor: InputNormalizer.fallbackZoomFactor(forScrollDeltaY: event.scrollingDeltaY),
            anchor: point
        )
    }

    override func magnify(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        inputHandler?.canvasDidZoom(factor: InputNormalizer.zoomFactor(forMagnification: event.magnification), anchor: point)
    }
}
