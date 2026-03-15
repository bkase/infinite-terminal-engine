import Foundation
import EngineABI
import Metal
import QuartzCore

struct CanvasRect {
    var x: Float
    var y: Float
    var w: Float
    var h: Float
    var color: UInt32
}

@MainActor
final class EngineRuntime: ObservableObject {
    @Published var statsSummary = "0 / 0"
    @Published var bootError: String?

    let renderProfileID: String

    private let bindings = EngineBindings.shared
    nonisolated(unsafe) private var engine: OpaquePointer?
    private var didInitialize = false
    private var queue: MTLCommandQueue?

    init() {
        let renderProfile: RenderProfile
        do {
            renderProfile = try RenderProfileCatalog.defaultProfile()
        } catch {
            renderProfileID = RenderProfileCatalog.defaultProfileID
            bootError = error.localizedDescription
            return
        }

        renderProfileID = renderProfile.id
        var handle: OpaquePointer?
        var config = ite_EngineConfig(
            abi_version: bindings.headerVersion(),
            max_rects: 512,
            max_visible_rects: 512,
            initial_width_px: 1280,
            initial_height_px: 720,
            min_zoom: 1.0e-9,
            max_zoom: 1.0e9
        )
        precondition(bindings.create(&handle, &config) == ite_EngineStatus_ok)
        engine = handle
        replaceRects(Self.demoRects)
    }

    deinit {
        bindings.destroy(engine)
    }

    func initializeIfNeeded(device: MTLDevice, queue: MTLCommandQueue) {
        guard bootError == nil else { return }
        guard !didInitialize, let engine else { return }
        self.queue = queue
        guard let metallibURL = Bundle.module.url(forResource: "rect_fill", withExtension: "metallib") else { return }
        let status = metallibURL.path.withCString { path in
            bindings.initWithMetallibPath(
                engine,
                Unmanaged.passUnretained(device).toOpaque(),
                Unmanaged.passUnretained(queue).toOpaque(),
                path
            )
        }
        didInitialize = status == ite_EngineStatus_ok
    }

    func replaceRects(_ rects: [CanvasRect]) {
        guard bootError == nil else { return }
        guard let engine else { return }
        var payloads = rects.map { rect in
            ite_Rect(x: rect.x, y: rect.y, w: rect.w, h: rect.h, color_rgba8: rect.color, _pad0: 0, _pad1: 0, _pad2: 0)
        }
        _ = payloads.withUnsafeMutableBufferPointer { buffer in
            bindings.replaceRects(engine, buffer.baseAddress!, buffer.count)
        }
    }

    func resize(width: Int, height: Int) {
        guard bootError == nil else { return }
        guard let engine else { return }
        _ = bindings.resize(engine, UInt32(width), UInt32(height))
    }

    func pan(delta: CGSize) {
        guard bootError == nil else { return }
        guard let engine else { return }
        _ = bindings.pan(engine, Float(delta.width), Float(delta.height))
    }

    func zoom(factor: Float, anchor: CGPoint) {
        guard bootError == nil else { return }
        guard let engine else { return }
        _ = bindings.zoom(engine, factor, Float(anchor.x), Float(anchor.y))
    }

    func render(drawable: CAMetalDrawable) {
        if let bootError {
            statsSummary = bootError
            return
        }
        guard let engine else { return }
        let status = bindings.render(engine, Unmanaged.passUnretained(drawable).toOpaque())
        if status == ite_EngineStatus_ok {
            updateStats()
        } else if let error = bindings.getLastError(engine) {
            statsSummary = String(cString: error)
        }
    }

    private func updateStats() {
        guard let engine else { return }
        var stats = ite_FrameStats()
        _ = bindings.getStats(engine, &stats)
        statsSummary = "\(stats.visible_rects) / \(stats.total_rects) visible • \(renderProfileID)"
    }

    static let demoRects: [CanvasRect] = stride(from: 0, to: 12, by: 1).flatMap { row in
        stride(from: 0, to: 12, by: 1).map { col in
            let red = UInt32((row * 19) & 0xff)
            let green = UInt32((col * 17) & 0xff)
            return CanvasRect(
                x: Float(col * 48),
                y: Float(row * 40),
                w: 36,
                h: 28,
                color: (red << 24) | (green << 16) | 0x55ff
            )
        }
    }
}
