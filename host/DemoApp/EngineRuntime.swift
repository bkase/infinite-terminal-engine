import Foundation
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
    private var camera = CanvasCamera()
    private var compositor: TerminalTextureCompositor?
    private var sharedTexture: MTLTexture?
    private var sharedTextureGeneration: UInt64 = 0

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
        camera.resize(width: 1280, height: 720)
        surfaces.replaceAll(with: Self.demoSurfaces(profileID: renderProfile.id))
    }

    func initializeIfNeeded(device: MTLDevice, queue: MTLCommandQueue) {
        _ = queue
        guard bootError == nil else { return }
        if compositor == nil {
            compositor = TerminalTextureCompositor(device: device)
        }
        if compositor == nil {
            bootError = "Missing texture compositor pipeline."
        }
    }

    func replaceSurfaces(_ surfaces: [TerminalSurface]) {
        self.surfaces.replaceAll(with: surfaces)
    }

    func setSharedTerminalTexture(_ texture: MTLTexture?, generation: UInt64) {
        guard generation >= sharedTextureGeneration else { return }
        sharedTexture = texture
        sharedTextureGeneration = generation
    }

    func resize(width: Int, height: Int) {
        camera.resize(width: width, height: height)
    }

    func pan(delta: CGSize) {
        camera.pan(delta: delta)
    }

    func zoom(factor: Float, anchor: CGPoint) {
        camera.zoom(by: factor, anchor: anchor)
    }

    func render(drawable: CAMetalDrawable) {
        if let bootError {
            statsSummary = bootError
            return
        }
        guard let compositor else { return }
        let frame = buildFrame()
        if compositor.render(drawable: drawable, camera: camera, quads: frame.quads, overlays: frame.overlays) {
            updateStats(visibleSurfaceCount: frame.quads.count)
        } else {
            statsSummary = "texture compositor render failed"
        }
    }

    private func updateStats(visibleSurfaceCount: Int) {
        statsSummary = "\(visibleSurfaceCount) / \(surfaces.count) visible • \(surfaces.count) surfaces • \(renderProfileID)"
    }

    private func buildFrame() -> (quads: [TerminalTextureQuad], overlays: [CanvasRect]) {
        let orderedIDs = surfaces.orderedSurfaceIDs()
        let quads = orderedIDs.compactMap { id -> TerminalTextureQuad? in
            guard
                let geometry = surfaces.geometry(for: id, profilesByID: profilesByID, backingScale: 1),
                let texture = sharedTexture
            else {
                return nil
            }
            return TerminalTextureQuad(frame: geometry.contentFrame, texture: texture)
        }
        let overlays = orderedIDs.compactMap { id -> [CanvasRect]? in
            guard
                let geometry = surfaces.geometry(for: id, profilesByID: profilesByID, backingScale: 1),
                let surface = surfaces.surface(id: id)
            else {
                return nil
            }

            let bodyColor: UInt32 = surface.flags.contains(.focused) ? 0x233a_50ff : 0x1b25_34ff
            let titleColor: UInt32 = surface.flags.contains(.focused) ? 0x4d9d_e0ff : 0x3144_5dff
            let borderThickness: Float = 2
            return [
                CanvasRect(
                    x: Float(geometry.frame.minX),
                    y: Float(geometry.frame.minY),
                    w: Float(geometry.frame.width),
                    h: Float(geometry.frame.height),
                    color: bodyColor
                ),
                CanvasRect(
                    x: Float(geometry.contentFrame.minX),
                    y: Float(geometry.contentFrame.minY),
                    w: Float(geometry.contentFrame.width),
                    h: Float(geometry.contentFrame.height),
                    color: 0x0000_00ff
                ),
                CanvasRect(
                    x: Float(geometry.titlebarFrame.minX),
                    y: Float(geometry.titlebarFrame.minY),
                    w: Float(geometry.titlebarFrame.width),
                    h: Float(geometry.titlebarFrame.height),
                    color: titleColor
                ),
                CanvasRect(
                    x: Float(geometry.contentFrame.minX - CGFloat(borderThickness)),
                    y: Float(geometry.contentFrame.minY - CGFloat(borderThickness)),
                    w: Float(geometry.contentFrame.width + CGFloat(borderThickness * 2)),
                    h: borderThickness,
                    color: titleColor
                ),
            ]
        }
        return (quads, overlays.flatMap { $0 })
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
