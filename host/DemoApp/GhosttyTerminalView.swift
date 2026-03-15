import AppKit
import GhosttyKit
import SwiftUI

struct GhosttyTerminalPane: NSViewRepresentable {
    @ObservedObject var adapter: GhosttySurfaceAdapter

    func makeNSView(context: Context) -> GhosttyHostingView {
        let view = GhosttyHostingView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.adapter = adapter
        return view
    }

    func updateNSView(_ nsView: GhosttyHostingView, context: Context) {
        nsView.adapter = adapter
        nsView.refreshSurfaceAttachment()
    }
}

final class GhosttyHostingView: NSView {
    weak var adapter: GhosttySurfaceAdapter?
    private var trackingAreaRef: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshSurfaceAttachment() {
        adapter?.attach(to: self)
        adapter?.updateSize()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshSurfaceAttachment()
    }

    override func layout() {
        super.layout()
        refreshSurfaceAttachment()
        updateTrackingAreas()
    }

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

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            adapter?.focusChanged(true)
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted {
            adapter?.focusChanged(false)
        }
        return accepted
    }

    override func keyDown(with event: NSEvent) {
        guard let adapter, let input = InputNormalizer.normalizedKeyInput(from: event) else {
            super.keyDown(with: event)
            return
        }
        _ = adapter.routeKeyInput(input)
    }

    override func keyUp(with event: NSEvent) {
        guard let adapter, let input = InputNormalizer.normalizedKeyInput(
            from: event,
            action: GhosttyKeyActionCode.release
        ) else {
            super.keyUp(with: event)
            return
        }
        _ = adapter.routeKeyInput(input)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        handleMouseButton(event, pressed: true)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        handleMouseButton(event, pressed: true)
    }

    override func otherMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        handleMouseButton(event, pressed: true)
    }

    override func mouseDragged(with event: NSEvent) {
        handleMouseMove(event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        handleMouseMove(event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        handleMouseMove(event)
    }

    override func mouseMoved(with event: NSEvent) {
        handleMouseMove(event)
    }

    override func mouseUp(with event: NSEvent) {
        handleMouseButton(event, pressed: false)
    }

    override func rightMouseUp(with event: NSEvent) {
        handleMouseButton(event, pressed: false)
    }

    override func otherMouseUp(with event: NSEvent) {
        handleMouseButton(event, pressed: false)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let adapter else {
            super.scrollWheel(with: event)
            return
        }
        _ = adapter.routeScroll(InputNormalizer.normalizedScrollInput(from: event))
    }

    @objc func copy(_ sender: Any?) {
        _ = sender
        adapter?.copySelectionToClipboard()
    }

    @objc func paste(_ sender: Any?) {
        _ = sender
        _ = adapter?.pasteRequest()
    }

    private func handleMouseButton(_ event: NSEvent, pressed: Bool) {
        guard let adapter else { return }
        _ = adapter.routeMouseButton(InputNormalizer.normalizedMouseButtonInput(from: event, in: self, pressed: pressed))
    }

    private func handleMouseMove(_ event: NSEvent) {
        guard let adapter else { return }
        let location = convert(event.locationInWindow, from: nil)
        _ = adapter.routeMouseMove(location: location, mods: InputNormalizer.ghosttyMods(from: event.modifierFlags))
    }
}
