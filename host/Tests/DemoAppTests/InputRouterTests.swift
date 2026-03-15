import CoreGraphics
import XCTest
@testable import DemoApp

final class InputRouterTests: XCTestCase {
    func testTopmostSurfaceHitPrefersHighestStackRank() throws {
        let profile = try RenderProfileCatalog.defaultProfile()
        var store = SurfaceStore()
        store.replaceAll(with: [
            makeSurface(id: "back", origin: CGPoint(x: 48, y: 48), stackRank: 0, profileID: profile.id),
            makeSurface(id: "front", origin: CGPoint(x: 48, y: 48), stackRank: 3, profileID: profile.id),
        ])

        let hit = InputRouter.topmostHit(
            screenPoint: CGPoint(x: 80, y: 96),
            surfaces: store,
            profilesByID: [profile.id: profile],
            camera: makeCamera(),
            backingScale: 2
        )

        XCTAssertEqual(hit?.surfaceID, TerminalSurfaceID("front"))
    }

    func testChromeRoutesToControlPlane() throws {
        let profile = try RenderProfileCatalog.defaultProfile()
        var store = SurfaceStore()
        store.replaceAll(with: [
            makeSurface(id: "surface", origin: CGPoint(x: 40, y: 40), stackRank: 0, profileID: profile.id),
        ])

        let decision = InputRouter.routePointerDown(
            screenPoint: CGPoint(x: 60, y: 54),
            surfaces: store,
            profilesByID: [profile.id: profile],
            camera: makeCamera(),
            backingScale: 2
        )

        XCTAssertEqual(decision, .surfaceChrome(surfaceID: TerminalSurfaceID("surface")))
    }

    func testContentRoutesToTerminalPlane() throws {
        let profile = try RenderProfileCatalog.defaultProfile()
        var store = SurfaceStore()
        store.replaceAll(with: [
            makeSurface(id: "surface", origin: CGPoint(x: 40, y: 40), stackRank: 0, profileID: profile.id),
        ])

        let decision = InputRouter.routePointerDown(
            screenPoint: CGPoint(x: 70, y: 110),
            surfaces: store,
            profilesByID: [profile.id: profile],
            camera: makeCamera(),
            backingScale: 2
        )

        guard case .terminalMouse(let surfaceID, let localPoint) = decision else {
            return XCTFail("expected terminal route")
        }
        XCTAssertEqual(surfaceID, TerminalSurfaceID("surface"))
        XCTAssertEqual(localPoint, CGPoint(x: 20, y: 32))
    }

    func testEmptyCanvasRoutesToCameraControl() throws {
        let profile = try RenderProfileCatalog.defaultProfile()
        var store = SurfaceStore()
        store.replaceAll(with: [
            makeSurface(id: "surface", origin: CGPoint(x: 40, y: 40), stackRank: 0, profileID: profile.id),
        ])

        let decision = InputRouter.routePointerDown(
            screenPoint: CGPoint(x: 900, y: 700),
            surfaces: store,
            profilesByID: [profile.id: profile],
            camera: makeCamera(),
            backingScale: 2
        )

        XCTAssertEqual(decision, .canvasPan)
    }

    func testFocusedKeyboardRoutesOnlyForAcceptingSurface() {
        var store = SurfaceStore()
        store.replaceAll(with: [
            TerminalSurface(
                id: TerminalSurfaceID("focused"),
                sessionID: "session-focused",
                origin: .zero,
                cols: 80,
                rows: 24,
                profileID: "default",
                stackRank: 0,
                flags: [.focused, .acceptsInput]
            ),
        ])

        XCTAssertEqual(
            InputRouter.routeKeyboard(focusedSurfaceID: TerminalSurfaceID("focused"), surfaces: store),
            .terminalKeyboard(surfaceID: TerminalSurfaceID("focused"))
        )
        XCTAssertEqual(
            InputRouter.routePaste(focusedSurfaceID: TerminalSurfaceID("missing"), surfaces: store),
            .ignored
        )
    }

    private func makeCamera() -> CanvasCamera {
        var camera = CanvasCamera()
        camera.resize(width: 1200, height: 800)
        return camera
    }

    private func makeSurface(
        id: String,
        origin: CGPoint,
        stackRank: Int,
        profileID: String
    ) -> TerminalSurface {
        TerminalSurface(
            id: TerminalSurfaceID(id),
            sessionID: "session-\(id)",
            origin: origin,
            cols: 80,
            rows: 24,
            profileID: profileID,
            stackRank: stackRank,
            flags: [.acceptsInput]
        )
    }
}
