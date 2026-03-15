import CoreGraphics
import EngineABI
import Foundation
import Metal
import QuartzCore

struct CanvasCamera: Equatable {
    var panX: Float = 0
    var panY: Float = 0
    var zoom: Float = 1
    var viewportWidth: UInt32 = 1280
    var viewportHeight: UInt32 = 720

    mutating func resize(width: Int, height: Int) {
        viewportWidth = UInt32(max(width, 1))
        viewportHeight = UInt32(max(height, 1))
    }

    mutating func pan(delta: CGSize) {
        panX -= Float(delta.width) / zoom
        panY -= Float(delta.height) / zoom
    }

    mutating func zoom(by factor: Float, anchor: CGPoint) {
        guard factor.isFinite, factor > 0 else { return }
        let before = screenToCanvas(anchor)
        let unclamped = zoom * factor
        zoom = min(max(unclamped.isFinite ? unclamped : (factor > 1 ? 1.0e9 : 1.0e-9), 1.0e-9), 1.0e9)
        let after = screenToCanvas(anchor)
        panX += Float(before.x - after.x)
        panY += Float(before.y - after.y)
    }

    func uniform() -> ite_CameraUniform {
        ite_CameraUniform(
            transform: (
                zoom,
                0,
                0,
                zoom,
                -panX * zoom,
                -panY * zoom
            ),
            viewport_width_px: viewportWidth,
            viewport_height_px: viewportHeight
        )
    }

    private func screenToCanvas(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: CGFloat(Float(point.x) / zoom + panX),
            y: CGFloat(Float(point.y) / zoom + panY)
        )
    }
}

struct TerminalTextureQuad {
    let frame: CGRect
    let texture: MTLTexture
}

private struct TexturedQuadInstance {
    var x: Float
    var y: Float
    var w: Float
    var h: Float
    var u0: Float
    var v0: Float
    var u1: Float
    var v1: Float
}

@MainActor
final class TerminalTextureCompositor {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let texturedPipeline: MTLRenderPipelineState
    private let rectPipeline: MTLRenderPipelineState

    init?(device: MTLDevice?) {
        guard
            let device,
            let commandQueue = device.makeCommandQueue()
        else {
            return nil
        }

        do {
            let library = try Self.loadLibrary(device: device)
            let texturedPipeline = try Self.makePipeline(
                device: device,
                library: library,
                vertexFunction: "textured_quad_vertex",
                fragmentFunction: "textured_quad_fragment"
            )
            let rectPipeline = try Self.makePipeline(
                device: device,
                library: library,
                vertexFunction: "rect_vertex",
                fragmentFunction: "rect_fragment"
            )
            self.device = device
            self.commandQueue = commandQueue
            self.texturedPipeline = texturedPipeline
            self.rectPipeline = rectPipeline
        } catch {
            return nil
        }
    }

    func makeRenderTarget(width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: max(width, 1),
            height: max(height, 1),
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        return device.makeTexture(descriptor: descriptor)
    }

    func render(
        targetTexture: MTLTexture,
        camera: CanvasCamera,
        quads: [TerminalTextureQuad],
        overlays: [CanvasRect]
    ) -> Bool {
        guard
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: Self.makeRenderPass(targetTexture: targetTexture))
        else {
            return false
        }

        let uniform = camera.uniform()
        drawTexturedQuads(quads, camera: uniform, encoder: encoder)
        drawOverlayRects(overlays, camera: uniform, encoder: encoder)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return commandBuffer.status == .completed && commandBuffer.error == nil
    }

    func render(
        drawable: CAMetalDrawable,
        camera: CanvasCamera,
        quads: [TerminalTextureQuad],
        overlays: [CanvasRect]
    ) -> Bool {
        guard
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: Self.makeRenderPass(targetTexture: drawable.texture))
        else {
            return false
        }

        let uniform = camera.uniform()
        drawTexturedQuads(quads, camera: uniform, encoder: encoder)
        drawOverlayRects(overlays, camera: uniform, encoder: encoder)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
        return true
    }

    private func drawTexturedQuads(
        _ quads: [TerminalTextureQuad],
        camera: ite_CameraUniform,
        encoder: MTLRenderCommandEncoder
    ) {
        guard !quads.isEmpty else { return }
        encoder.setRenderPipelineState(texturedPipeline)
        var uniform = camera
        encoder.setVertexBytes(&uniform, length: MemoryLayout<ite_CameraUniform>.stride, index: 0)

        for quad in quads {
            var instance = TexturedQuadInstance(
                x: Float(quad.frame.minX),
                y: Float(quad.frame.minY),
                w: Float(quad.frame.width),
                h: Float(quad.frame.height),
                u0: 0,
                v0: 0,
                u1: 1,
                v1: 1
            )
            encoder.setVertexBytes(&instance, length: MemoryLayout<TexturedQuadInstance>.stride, index: 1)
            encoder.setFragmentTexture(quad.texture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
    }

    private func drawOverlayRects(
        _ overlays: [CanvasRect],
        camera: ite_CameraUniform,
        encoder: MTLRenderCommandEncoder
    ) {
        guard !overlays.isEmpty else { return }
        encoder.setRenderPipelineState(rectPipeline)
        var uniform = camera
        encoder.setVertexBytes(&uniform, length: MemoryLayout<ite_CameraUniform>.stride, index: 0)
        encoder.setVertexBytes(overlays, length: MemoryLayout<CanvasRect>.stride * overlays.count, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: overlays.count)
    }

    private static func makePipeline(
        device: MTLDevice,
        library: MTLLibrary,
        vertexFunction: String,
        fragmentFunction: String
    ) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        descriptor.vertexFunction = library.makeFunction(name: vertexFunction)
        descriptor.fragmentFunction = library.makeFunction(name: fragmentFunction)
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func loadLibrary(device: MTLDevice) throws -> MTLLibrary {
        var candidateURLs: [URL] = []
        if let bundled = Bundle.module.url(forResource: "rect_fill", withExtension: "metallib") {
            candidateURLs.append(bundled)
        }

        let staged = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("host/DemoApp/Resources/rect_fill.metallib")
        candidateURLs.append(staged)

        for url in candidateURLs {
            guard let library = try? device.makeLibrary(URL: url) else { continue }
            if library.makeFunction(name: "textured_quad_vertex") != nil,
                library.makeFunction(name: "textured_quad_fragment") != nil
            {
                return library
            }
        }

        throw NSError(domain: "TerminalTextureCompositor", code: 1)
    }

    private static func makeRenderPass(targetTexture: MTLTexture) -> MTLRenderPassDescriptor {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = targetTexture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.04, green: 0.05, blue: 0.06, alpha: 1)
        return descriptor
    }
}
