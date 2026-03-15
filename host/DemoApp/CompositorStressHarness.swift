import CoreGraphics
import Foundation
import Metal

struct CompositorStressMetrics {
    let totalSurfaces: Int
    let visibleSurfaces: Int
    let culledSurfaces: Int
    let occludedSurfaces: Int
    let textureMemoryBytes: Int
    let averageFrameBuildMicros: Double
    let averageFrameRenderMillis: Double
}

struct PublishChurnMetrics {
    let surfaceCount: Int
    let cycles: Int
    let completedPublishes: Int
    let finalGeneration: UInt64
}

enum CompositorStressHarness {
    static func makeMixedSizeSurfaces(profileID: String, count: Int = 50) -> [TerminalSurface] {
        let widths = [64, 72, 80, 88, 96]
        let heights = [18, 20, 24, 28]

        return (0..<count).map { index in
            let column = index % 5
            let row = index / 5
            return TerminalSurface(
                id: TerminalSurfaceID("surface-\(index)"),
                sessionID: "session-\(index)",
                origin: CGPoint(x: 48 + (column * 180), y: 48 + (row * 110)),
                cols: widths[index % widths.count],
                rows: heights[index % heights.count],
                profileID: profileID,
                stackRank: index,
                flags: [.acceptsInput]
            )
        }
    }

    static func makeHeavyOverlapSurfaces(profileID: String, count: Int = 50) -> [TerminalSurface] {
        (0..<count).map { index in
            TerminalSurface(
                id: TerminalSurfaceID("overlap-\(index)"),
                sessionID: "session-overlap-\(index)",
                origin: CGPoint(x: 72, y: 72),
                cols: 100,
                rows: 30,
                profileID: profileID,
                stackRank: index,
                flags: [.acceptsInput]
            )
        }
    }

    static func measureVisibility(
        surfaces: [TerminalSurface],
        profilesByID: [String: RenderProfile],
        camera: CanvasCamera,
        backingScale: CGFloat,
        iterations: Int = 120
    ) -> CompositorStressMetrics {
        var store = SurfaceStore()
        store.replaceAll(with: surfaces)
        let budget = TextureBudgetPolicy.assessRoom(
            surfaces: store,
            profilesByID: profilesByID,
            backingScale: backingScale
        )

        let clock = ContinuousClock()
        var totalMicros = 0.0
        var finalReport = VisibleSurfaceReport(visibleSurfaces: [], culledCount: 0, occludedCount: 0)

        for _ in 0..<max(iterations, 1) {
            let start = clock.now
            finalReport = VisibleSurfaceList.analyze(
                surfaces: store,
                profilesByID: profilesByID,
                camera: camera,
                backingScale: backingScale
            )
            totalMicros += Double(start.duration(to: clock.now).components.attoseconds) / 1_000_000_000_000.0
        }

        return CompositorStressMetrics(
            totalSurfaces: surfaces.count,
            visibleSurfaces: finalReport.visibleSurfaces.count,
            culledSurfaces: finalReport.culledCount,
            occludedSurfaces: finalReport.occludedCount,
            textureMemoryBytes: budget.totalBytes,
            averageFrameBuildMicros: totalMicros / Double(max(iterations, 1)),
            averageFrameRenderMillis: 0
        )
    }

    @MainActor
    static func measureRender(
        visibleSurfaces: [VisibleTerminalSurface],
        camera: CanvasCamera,
        iterations: Int = 12
    ) throws -> Double {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "CompositorStressHarness", code: 1)
        }
        guard let compositor = TerminalTextureCompositor(device: device) else {
            throw NSError(domain: "CompositorStressHarness", code: 2)
        }
        guard let target = compositor.makeRenderTarget(
            width: Int(camera.viewportWidth),
            height: Int(camera.viewportHeight)
        ) else {
            throw NSError(domain: "CompositorStressHarness", code: 3)
        }

        let quads = visibleSurfaces.enumerated().compactMap { index, surface -> TerminalTextureQuad? in
            guard let texture = makeSolidTexture(
                device: device,
                width: Int(surface.geometry.pixelSize.width),
                height: Int(surface.geometry.pixelSize.height),
                seed: index
            ) else {
                return nil
            }
            return TerminalTextureQuad(frame: surface.geometry.contentFrame, texture: texture)
        }

        let overlays = visibleSurfaces.map { surface in
            CanvasRect(
                x: Float(surface.geometry.titlebarFrame.minX),
                y: Float(surface.geometry.titlebarFrame.minY),
                w: Float(surface.geometry.titlebarFrame.width),
                h: Float(surface.geometry.titlebarFrame.height),
                color: 0x3144_5dff
            )
        }

        let clock = ContinuousClock()
        var totalMillis = 0.0
        for _ in 0..<max(iterations, 1) {
            let start = clock.now
            _ = compositor.render(targetTexture: target, camera: camera, quads: quads, overlays: overlays)
            totalMillis += Double(start.duration(to: clock.now).components.attoseconds) / 1_000_000_000_000_000.0
        }
        return totalMillis / Double(max(iterations, 1))
    }

    static func simulatePublishChurn(surfaceCount: Int = 50, cycles: Int = 20) -> PublishChurnMetrics {
        var states = Array(repeating: TerminalTexturePublishState<Int>(), count: surfaceCount)
        var completedPublishes = 0
        var finalGeneration: UInt64 = 0

        for cycle in 0..<cycles {
            for index in states.indices {
                guard let generation = states[index].beginPublish(
                    backTexture: cycle * 1000 + index,
                    size: CGSize(width: 1280, height: 800)
                ) else {
                    continue
                }
                if states[index].completePublish(generation) {
                    completedPublishes += 1
                    finalGeneration = max(finalGeneration, states[index].frontGeneration)
                }
            }
        }

        return PublishChurnMetrics(
            surfaceCount: surfaceCount,
            cycles: cycles,
            completedPublishes: completedPublishes,
            finalGeneration: finalGeneration
        )
    }

    private static func makeSolidTexture(
        device: MTLDevice,
        width: Int,
        height: Int,
        seed: Int
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: max(width, 1),
            height: max(height, 1),
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        let r = UInt8((seed * 53) % 255)
        let g = UInt8((seed * 97) % 255)
        let b = UInt8((seed * 193) % 255)
        let pixel = [r, g, b, UInt8(255)]
        let bytes = Array(repeating: pixel, count: max(width, 1) * max(height, 1)).flatMap { $0 }
        texture.replace(
            region: MTLRegionMake2D(0, 0, max(width, 1), max(height, 1)),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: max(width, 1) * 4
        )
        return texture
    }
}
