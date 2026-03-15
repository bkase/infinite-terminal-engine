import AppKit
import MetalKit

@MainActor
protocol CanvasInputHandler: AnyObject {
    func canvasPointerDown(at point: CGPoint, event: NSEvent)
    func canvasPointerDragged(to point: CGPoint, event: NSEvent)
    func canvasPointerUp(at point: CGPoint, event: NSEvent)
    func canvasPointerMoved(to point: CGPoint, event: NSEvent)
    func canvasScroll(at point: CGPoint, event: NSEvent)
    func canvasMagnify(factor: Float, anchor: CGPoint)
    func canvasKeyDown(_ event: NSEvent)
    func canvasKeyUp(_ event: NSEvent)
    func canvasCopy()
    func canvasPaste()
}

final class MetalCanvasView: MTKView {
    weak var inputHandler: CanvasInputHandler?
    private var trackingAreaRef: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        inputHandler?.canvasPointerDown(at: convert(event.locationInWindow, from: nil), event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        inputHandler?.canvasPointerDragged(to: convert(event.locationInWindow, from: nil), event: event)
    }

    override func mouseUp(with event: NSEvent) {
        inputHandler?.canvasPointerUp(at: convert(event.locationInWindow, from: nil), event: event)
    }

    override func mouseMoved(with event: NSEvent) {
        inputHandler?.canvasPointerMoved(to: convert(event.locationInWindow, from: nil), event: event)
    }

    override func scrollWheel(with event: NSEvent) {
        inputHandler?.canvasScroll(at: convert(event.locationInWindow, from: nil), event: event)
    }

    override func magnify(with event: NSEvent) {
        inputHandler?.canvasMagnify(
            factor: InputNormalizer.zoomFactor(forMagnification: event.magnification),
            anchor: convert(event.locationInWindow, from: nil)
        )
    }

    override func keyDown(with event: NSEvent) {
        inputHandler?.canvasKeyDown(event)
    }

    override func keyUp(with event: NSEvent) {
        inputHandler?.canvasKeyUp(event)
    }

    @objc func copy(_ sender: Any?) {
        _ = sender
        inputHandler?.canvasCopy()
    }

    @objc func paste(_ sender: Any?) {
        _ = sender
        inputHandler?.canvasPaste()
    }
}
