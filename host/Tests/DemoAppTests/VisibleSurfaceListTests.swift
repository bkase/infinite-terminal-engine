import XCTest

@testable import DemoApp

final class VisibleSurfaceListTests: XCTestCase {
    func testViewportCullingKeepsBoundaryIntersections() throws {
        let profile = try RenderProfileCatalog.defaultProfile()
        var store = SurfaceStore()
        store.replaceAll(with: [
            makeSurface(id: "inside", origin: CGPoint(x: 10, y: 10), stackRank: 0, profileID: profile.id),
            makeSurface(id: "touching", origin: CGPoint(x: 560, y: 10), stackRank: 1, profileID: profile.id),
            makeSurface(id: "outside", origin: CGPoint(x: 1200, y: 10), stackRank: 2, profileID: profile.id),
        ])

        var camera = CanvasCamera()
        camera.resize(width: 800, height: 600)

        let visible = VisibleSurfaceList.build(
            surfaces: store,
            profilesByID: [profile.id: profile],
            camera: camera
        )

        XCTAssertEqual(visible.map(\.surfaceID), [
            TerminalSurfaceID("inside"),
            TerminalSurfaceID("touching"),
        ])
    }

    func testPainterOrderIsPreservedForVisibleSurvivors() throws {
        let profile = try RenderProfileCatalog.defaultProfile()
        var store = SurfaceStore()
        store.replaceAll(with: [
            makeSurface(id: "back", origin: CGPoint(x: 10, y: 10), stackRank: 0, profileID: profile.id),
            makeSurface(id: "front", origin: CGPoint(x: 120, y: 60), stackRank: 3, profileID: profile.id),
        ])

        var camera = CanvasCamera()
        camera.resize(width: 1000, height: 800)

        let visible = VisibleSurfaceList.build(
            surfaces: store,
            profilesByID: [profile.id: profile],
            camera: camera
        )

        XCTAssertEqual(visible.map(\.surfaceID), [
            TerminalSurfaceID("back"),
            TerminalSurfaceID("front"),
        ])
    }

    func testFullyCoveredOpaqueSurfaceIsSkipped() throws {
        let profile = try RenderProfileCatalog.defaultProfile()
        var store = SurfaceStore()
        store.replaceAll(with: [
            makeSurface(id: "back", origin: CGPoint(x: 32, y: 32), stackRank: 0, profileID: profile.id),
            makeSurface(id: "front", origin: CGPoint(x: 32, y: 32), stackRank: 1, profileID: profile.id),
        ])

        var camera = CanvasCamera()
        camera.resize(width: 1000, height: 800)

        let visible = VisibleSurfaceList.build(
            surfaces: store,
            profilesByID: [profile.id: profile],
            camera: camera
        )

        XCTAssertEqual(visible.map(\.surfaceID), [TerminalSurfaceID("front")])
    }

    func testPartialOverlapDoesNotTriggerFalseSkip() throws {
        let profile = try RenderProfileCatalog.defaultProfile()
        var store = SurfaceStore()
        store.replaceAll(with: [
            makeSurface(id: "back", origin: CGPoint(x: 32, y: 32), stackRank: 0, profileID: profile.id),
            makeSurface(id: "front", origin: CGPoint(x: 140, y: 40), stackRank: 1, profileID: profile.id),
        ])

        var camera = CanvasCamera()
        camera.resize(width: 1000, height: 800)

        let visible = VisibleSurfaceList.build(
            surfaces: store,
            profilesByID: [profile.id: profile],
            camera: camera
        )

        XCTAssertEqual(visible.map(\.surfaceID), [
            TerminalSurfaceID("back"),
            TerminalSurfaceID("front"),
        ])
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
