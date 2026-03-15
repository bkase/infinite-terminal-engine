import Metal
import XCTest

@testable import DemoApp

@MainActor
final class TerminalTextureCompositorTests: XCTestCase {
    func testOneSurfaceRendersRealTerminalTexture() throws {
        let compositor = try makeCompositor()
        let target = try makeTargetTexture(compositor: compositor, width: 64, height: 64)
        let texture = try makeSolidTexture(color: (255, 0, 0, 255), width: 8, height: 8)

        let didRender = compositor.render(
            targetTexture: target,
            camera: makeCamera(width: 64, height: 64),
            quads: [TerminalTextureQuad(frame: CGRect(x: 8, y: 8, width: 32, height: 32), texture: texture)],
            overlays: []
        )

        XCTAssertTrue(didRender)
        XCTAssertEqual(samplePixel(texture: target, x: 20, y: 20), SIMD4<UInt8>(255, 0, 0, 255))
    }

    func testOverlapUsesStackOrderForTerminalTextures() throws {
        let compositor = try makeCompositor()
        let target = try makeTargetTexture(compositor: compositor, width: 80, height: 80)
        let back = try makeSolidTexture(color: (255, 0, 0, 255), width: 8, height: 8)
        let front = try makeSolidTexture(color: (0, 255, 0, 255), width: 8, height: 8)

        let didRender = compositor.render(
            targetTexture: target,
            camera: makeCamera(width: 80, height: 80),
            quads: [
                TerminalTextureQuad(frame: CGRect(x: 8, y: 8, width: 48, height: 48), texture: back),
                TerminalTextureQuad(frame: CGRect(x: 24, y: 24, width: 40, height: 40), texture: front),
            ],
            overlays: []
        )

        XCTAssertTrue(didRender)
        XCTAssertEqual(samplePixel(texture: target, x: 40, y: 40), SIMD4<UInt8>(0, 255, 0, 255))
    }

    func testOverlaySmokeDoesNotCorruptTextureSampling() throws {
        let compositor = try makeCompositor()
        let target = try makeTargetTexture(compositor: compositor, width: 96, height: 96)
        let texture = try makeSolidTexture(color: (0, 0, 255, 255), width: 8, height: 8)

        let didRender = compositor.render(
            targetTexture: target,
            camera: makeCamera(width: 96, height: 96),
            quads: [TerminalTextureQuad(frame: CGRect(x: 16, y: 20, width: 56, height: 48), texture: texture)],
            overlays: [CanvasRect(x: 16, y: 8, w: 56, h: 12, color: 0xffff_ffff)]
        )

        XCTAssertTrue(didRender)
        XCTAssertEqual(samplePixel(texture: target, x: 24, y: 30), SIMD4<UInt8>(0, 0, 255, 255))
        XCTAssertEqual(samplePixel(texture: target, x: 24, y: 12), SIMD4<UInt8>(255, 255, 255, 255))
    }

    private func makeCompositor() throws -> TerminalTextureCompositor {
        try XCTUnwrap(TerminalTextureCompositor(device: MTLCreateSystemDefaultDevice()))
    }

    private func makeTargetTexture(
        compositor: TerminalTextureCompositor,
        width: Int,
        height: Int
    ) throws -> MTLTexture {
        try XCTUnwrap(compositor.makeRenderTarget(width: width, height: height))
    }

    private func makeSolidTexture(
        color: (UInt8, UInt8, UInt8, UInt8),
        width: Int,
        height: Int
    ) throws -> MTLTexture {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable")
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead]
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let pixel = [color.0, color.1, color.2, color.3]
        let bytes = Array(repeating: pixel, count: width * height).flatMap { $0 }
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: width * 4
        )
        return texture
    }

    private func makeCamera(width: Int, height: Int) -> CanvasCamera {
        var camera = CanvasCamera()
        camera.resize(width: width, height: height)
        return camera
    }

    private func samplePixel(texture: MTLTexture, x: Int, y: Int) -> SIMD4<UInt8> {
        var pixel = [UInt8](repeating: 0, count: 4)
        texture.getBytes(
            &pixel,
            bytesPerRow: 4,
            from: MTLRegionMake2D(x, y, 1, 1),
            mipmapLevel: 0
        )
        return SIMD4(pixel[0], pixel[1], pixel[2], pixel[3])
    }
}
