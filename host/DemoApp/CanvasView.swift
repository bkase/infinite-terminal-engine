import AppKit
import MetalKit
import SwiftUI

struct CanvasView: NSViewRepresentable {
    @ObservedObject var runtime: EngineRuntime

    func makeCoordinator() -> Coordinator {
        Coordinator(runtime: runtime)
    }

    func makeNSView(context: Context) -> MetalCanvasView {
        let view = MetalCanvasView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        guard let device = view.device else { return view }
        view.framebufferOnly = false
        view.clearColor = MTLClearColorMake(0.04, 0.05, 0.06, 1)
        view.colorPixelFormat = .rgba8Unorm
        view.preferredFramesPerSecond = 120
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.delegate = context.coordinator
        view.inputHandler = context.coordinator
        context.coordinator.attach(view: view, device: device)
        return view
    }

    func updateNSView(_ nsView: MetalCanvasView, context: Context) {
        _ = nsView
    }

    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate, CanvasInputHandler {
        private let runtime: EngineRuntime
        private var queue: MTLCommandQueue?

        init(runtime: EngineRuntime) {
            self.runtime = runtime
        }

        func attach(view: MTKView, device: MTLDevice) {
            queue = device.makeCommandQueue()
            if let queue {
                runtime.initializeIfNeeded(device: device, queue: queue)
            }
            runtime.resize(width: Int(view.drawableSize.width), height: Int(view.drawableSize.height))
        }

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable else { return }
            runtime.render(texture: drawable.texture)
            runtime.present(drawable: drawable)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            runtime.resize(width: Int(size.width), height: Int(size.height))
        }

        func canvasDidPan(delta: CGSize) {
            runtime.pan(delta: delta)
        }

        func canvasDidZoom(factor: Float, anchor: CGPoint) {
            runtime.zoom(factor: factor, anchor: anchor)
        }
    }
}
