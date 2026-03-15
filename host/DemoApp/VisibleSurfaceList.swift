import CoreGraphics

struct VisibleTerminalSurface: Equatable {
    let surfaceID: TerminalSurfaceID
    let geometry: TerminalSurfaceGeometry
    let stackRank: Int
}

enum VisibleSurfaceList {
    static func build(
        surfaces: SurfaceStore,
        profilesByID: [String: RenderProfile],
        camera: CanvasCamera,
        backingScale: CGFloat = 1
    ) -> [VisibleTerminalSurface] {
        let ordered = surfaces.orderedSurfaceIDs().compactMap { id -> VisibleTerminalSurface? in
            guard
                let surface = surfaces.surface(id: id),
                !surface.flags.contains(.hidden),
                let geometry = surfaces.geometry(for: id, profilesByID: profilesByID, backingScale: backingScale)
            else {
                return nil
            }

            guard geometry.frame.intersects(camera.viewportRect) else { return nil }
            return VisibleTerminalSurface(surfaceID: id, geometry: geometry, stackRank: surface.stackRank)
        }

        var occludingFrames: [CGRect] = []
        var survivors: [VisibleTerminalSurface] = []

        for visibleSurface in ordered.reversed() {
            guard !occludingFrames.contains(where: { $0.contains(visibleSurface.geometry.frame) }) else {
                continue
            }
            survivors.append(visibleSurface)
            occludingFrames.append(visibleSurface.geometry.frame)
        }

        return survivors.reversed()
    }
}
