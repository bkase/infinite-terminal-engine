import AppKit
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
    }
}
