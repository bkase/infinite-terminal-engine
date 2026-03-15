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
    private(set) var surfaces = SurfaceStore()
    private var profilesByID: [String: RenderProfile] = [:]

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
        profilesByID = [renderProfile.id: renderProfile]
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
        surfaces.replaceAll(with: Self.demoSurfaces(profileID: renderProfile.id))
        syncSceneRects()
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

    func replaceSurfaces(_ surfaces: [TerminalSurface]) {
        self.surfaces.replaceAll(with: surfaces)
        syncSceneRects()
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
        statsSummary = "\(stats.visible_rects) / \(stats.total_rects) visible • \(surfaces.count) surfaces • \(renderProfileID)"
    }

    private func syncSceneRects(backingScale: CGFloat = 1) {
        let sceneRects = surfaces.orderedSurfaceIDs().compactMap { id -> [CanvasRect]? in
            guard let geometry = surfaces.geometry(for: id, profilesByID: profilesByID, backingScale: backingScale),
                let surface = surfaces.surface(id: id)
            else {
                return nil
            }

            let bodyColor: UInt32 = surface.flags.contains(.focused) ? 0x233a50ff : 0x1b2534ff
            let titleColor: UInt32 = surface.flags.contains(.focused) ? 0x4d9de0ff : 0x31445dff
            let borderInset: Float = 1
            let bodyRect = CanvasRect(
                x: Float(geometry.frame.minX),
                y: Float(geometry.frame.minY),
                w: Float(geometry.frame.width),
                h: Float(geometry.frame.height),
                color: bodyColor
            )
            let titleRect = CanvasRect(
                x: Float(geometry.titlebarFrame.minX),
                y: Float(geometry.titlebarFrame.minY),
                w: Float(geometry.titlebarFrame.width),
                h: Float(geometry.titlebarFrame.height),
                color: titleColor
            )
            let contentRect = CanvasRect(
                x: Float(geometry.contentFrame.minX - CGFloat(borderInset)),
                y: Float(geometry.contentFrame.minY - CGFloat(borderInset)),
                w: Float(geometry.contentFrame.width + CGFloat(borderInset * 2)),
                h: Float(geometry.contentFrame.height + CGFloat(borderInset * 2)),
                color: 0x0f1722ff
            )
            return [bodyRect, titleRect, contentRect]
        }
        replaceRects(sceneRects.flatMap { $0 })
    }

    static func demoSurfaces(profileID: String) -> [TerminalSurface] {
        [
            TerminalSurface(
                id: TerminalSurfaceID("surface-alpha"),
                sessionID: "session-alpha",
                origin: CGPoint(x: 56, y: 52),
                cols: 80,
                rows: 24,
                profileID: profileID,
                stackRank: 0,
                flags: [.focused, .acceptsInput]
            ),
            TerminalSurface(
                id: TerminalSurfaceID("surface-beta"),
                sessionID: "session-beta",
                origin: CGPoint(x: 220, y: 180),
                cols: 72,
                rows: 20,
                profileID: profileID,
                stackRank: 1,
                flags: [.acceptsInput]
            ),
            TerminalSurface(
                id: TerminalSurfaceID("surface-gamma"),
                sessionID: "session-gamma",
                origin: CGPoint(x: 470, y: 88),
                cols: 64,
                rows: 18,
                profileID: profileID,
                stackRank: 2,
                flags: [.acceptsInput]
            ),
        ]
    }
}
