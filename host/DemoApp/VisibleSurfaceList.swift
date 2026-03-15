import CoreGraphics

struct VisibleTerminalSurface: Equatable {
    let surfaceID: TerminalSurfaceID
    let geometry: TerminalSurfaceGeometry
    let stackRank: Int
}

struct VisibleSurfaceReport: Equatable {
    let visibleSurfaces: [VisibleTerminalSurface]
    let culledCount: Int
    let occludedCount: Int
}

enum VisibleSurfaceList {
    static func build(
        surfaces: SurfaceStore,
        profilesByID: [String: RenderProfile],
        camera: CanvasCamera,
        backingScale: CGFloat = 1
    ) -> [VisibleTerminalSurface] {
        analyze(
            surfaces: surfaces,
            profilesByID: profilesByID,
            camera: camera,
            backingScale: backingScale
        ).visibleSurfaces
    }

    static func analyze(
        surfaces: SurfaceStore,
        profilesByID: [String: RenderProfile],
        camera: CanvasCamera,
        backingScale: CGFloat = 1
    ) -> VisibleSurfaceReport {
        var culledCount = 0
        let ordered = surfaces.orderedSurfaceIDs().compactMap { id -> VisibleTerminalSurface? in
            guard
                let surface = surfaces.surface(id: id),
                !surface.flags.contains(.hidden),
                let geometry = surfaces.geometry(for: id, profilesByID: profilesByID, backingScale: backingScale)
            else {
                return nil
            }

            guard geometry.frame.intersects(camera.viewportRect) else {
                culledCount += 1
                return nil
            }
            return VisibleTerminalSurface(surfaceID: id, geometry: geometry, stackRank: surface.stackRank)
        }

        var occludingFrames: [CGRect] = []
        var survivors: [VisibleTerminalSurface] = []
        var occludedCount = 0

        for visibleSurface in ordered.reversed() {
            guard !occludingFrames.contains(where: { $0.contains(visibleSurface.geometry.frame) }) else {
                occludedCount += 1
                continue
            }
            survivors.append(visibleSurface)
            occludingFrames.append(visibleSurface.geometry.frame)
        }

        return VisibleSurfaceReport(
            visibleSurfaces: survivors.reversed(),
            culledCount: culledCount,
            occludedCount: occludedCount
        )
    }
}
