import AppKit
import CoreGraphics
import Foundation

enum SurfaceHitRegion: Equatable {
    case chrome
    case content(localPoint: CGPoint)
}

struct SurfaceHit: Equatable {
    let surfaceID: TerminalSurfaceID
    let region: SurfaceHitRegion
}

enum InputRoutingDecision: Equatable {
    case canvasPan
    case canvasZoom
    case terminalKeyboard(surfaceID: TerminalSurfaceID)
    case terminalCopy(surfaceID: TerminalSurfaceID)
    case terminalPaste(surfaceID: TerminalSurfaceID)
    case terminalMouse(surfaceID: TerminalSurfaceID, localPoint: CGPoint)
    case terminalScroll(surfaceID: TerminalSurfaceID, localPoint: CGPoint)
    case surfaceChrome(surfaceID: TerminalSurfaceID)
    case ignored
}

enum InputRouter {
    static func topmostHit(
        screenPoint: CGPoint,
        surfaces: SurfaceStore,
        profilesByID: [String: RenderProfile],
        camera: CanvasCamera,
        backingScale: CGFloat
    ) -> SurfaceHit? {
        let canvasPoint = camera.canvasPoint(fromScreen: screenPoint)
        let visible = VisibleSurfaceList.build(
            surfaces: surfaces,
            profilesByID: profilesByID,
            camera: camera,
            backingScale: backingScale
        )

        for visibleSurface in visible.reversed() {
            let geometry = visibleSurface.geometry
            guard geometry.frame.contains(canvasPoint) else { continue }
            if geometry.contentFrame.contains(canvasPoint) {
                return SurfaceHit(
                    surfaceID: visibleSurface.surfaceID,
                    region: .content(
                        localPoint: CGPoint(
                            x: canvasPoint.x - geometry.contentFrame.minX,
                            y: canvasPoint.y - geometry.contentFrame.minY
                        )
                    )
                )
            }
            return SurfaceHit(surfaceID: visibleSurface.surfaceID, region: .chrome)
        }

        return nil
    }

    static func routePointerDown(
        screenPoint: CGPoint,
        surfaces: SurfaceStore,
        profilesByID: [String: RenderProfile],
        camera: CanvasCamera,
        backingScale: CGFloat
    ) -> InputRoutingDecision {
        switch topmostHit(
            screenPoint: screenPoint,
            surfaces: surfaces,
            profilesByID: profilesByID,
            camera: camera,
            backingScale: backingScale
        ) {
        case .some(let hit):
            switch hit.region {
            case .chrome:
                return .surfaceChrome(surfaceID: hit.surfaceID)
            case .content(let localPoint):
                return .terminalMouse(surfaceID: hit.surfaceID, localPoint: localPoint)
            }
        case .none:
            return .canvasPan
        }
    }

    static func routeScroll(
        screenPoint: CGPoint,
        surfaces: SurfaceStore,
        profilesByID: [String: RenderProfile],
        camera: CanvasCamera,
        backingScale: CGFloat
    ) -> InputRoutingDecision {
        switch topmostHit(
            screenPoint: screenPoint,
            surfaces: surfaces,
            profilesByID: profilesByID,
            camera: camera,
            backingScale: backingScale
        ) {
        case .some(let hit):
            switch hit.region {
            case .chrome:
                return .canvasZoom
            case .content(let localPoint):
                return .terminalScroll(surfaceID: hit.surfaceID, localPoint: localPoint)
            }
        case .none:
            return .canvasZoom
        }
    }

    static func routeKeyboard(
        focusedSurfaceID: TerminalSurfaceID?,
        surfaces: SurfaceStore
    ) -> InputRoutingDecision {
        guard
            let focusedSurfaceID,
            let surface = surfaces.surface(id: focusedSurfaceID),
            surface.flags.contains(.acceptsInput),
            !surface.flags.contains(.hidden)
        else {
            return .ignored
        }
        return .terminalKeyboard(surfaceID: focusedSurfaceID)
    }

    static func routePaste(
        focusedSurfaceID: TerminalSurfaceID?,
        surfaces: SurfaceStore
    ) -> InputRoutingDecision {
        guard case .terminalKeyboard(let surfaceID) = routeKeyboard(
            focusedSurfaceID: focusedSurfaceID,
            surfaces: surfaces
        ) else {
            return .ignored
        }
        return .terminalPaste(surfaceID: surfaceID)
    }

    static func routeCopy(
        focusedSurfaceID: TerminalSurfaceID?,
        surfaces: SurfaceStore
    ) -> InputRoutingDecision {
        guard case .terminalKeyboard(let surfaceID) = routeKeyboard(
            focusedSurfaceID: focusedSurfaceID,
            surfaces: surfaces
        ) else {
            return .ignored
        }
        return .terminalCopy(surfaceID: surfaceID)
    }
}
