import XCTest
@testable import DemoApp

@MainActor
final class CompositorStressHarnessTests: XCTestCase {
    func testMixedSizeSceneStaysWithinStep2RoomBudget() throws {
        let profile = try RenderProfileCatalog.defaultProfile()
        var camera = CanvasCamera()
        camera.resize(width: 1600, height: 1200)

        let metrics = CompositorStressHarness.measureVisibility(
            surfaces: CompositorStressHarness.makeMixedSizeSurfaces(profileID: profile.id),
            profilesByID: [profile.id: profile],
            camera: camera,
            backingScale: 2
        )

        XCTAssertEqual(metrics.totalSurfaces, 50)
        XCTAssertLessThanOrEqual(metrics.visibleSurfaces, 50)
        XCTAssertLessThan(metrics.textureMemoryBytes, TextureBudgetPolicy.roomBudgetBytes)
        XCTAssertLessThan(metrics.averageFrameBuildMicros, 2_000)
    }

    func testHeavyOverlapSkipsCoveredSurfacesDeterministically() throws {
        let profile = try RenderProfileCatalog.defaultProfile()
        var camera = CanvasCamera()
        camera.resize(width: 1600, height: 1200)

        let metrics = CompositorStressHarness.measureVisibility(
            surfaces: CompositorStressHarness.makeHeavyOverlapSurfaces(profileID: profile.id),
            profilesByID: [profile.id: profile],
            camera: camera,
            backingScale: 2
        )

        XCTAssertEqual(metrics.visibleSurfaces, 1)
        XCTAssertEqual(metrics.occludedSurfaces, 49)
    }

    func testCameraMotionAndRenderStayBoundedForVisibleScene() throws {
        let profile = try RenderProfileCatalog.defaultProfile()
        var camera = CanvasCamera()
        camera.resize(width: 1600, height: 1200)
        camera.pan(delta: CGSize(width: -120, height: -80))
        camera.zoom(by: 1.15, anchor: CGPoint(x: 800, y: 600))

        var store = SurfaceStore()
        store.replaceAll(with: CompositorStressHarness.makeMixedSizeSurfaces(profileID: profile.id))
        let report = VisibleSurfaceList.analyze(
            surfaces: store,
            profilesByID: [profile.id: profile],
            camera: camera,
            backingScale: 2
        )

        let averageRenderMillis = try CompositorStressHarness.measureRender(
            visibleSurfaces: report.visibleSurfaces,
            camera: camera
        )

        XCTAssertGreaterThan(report.visibleSurfaces.count, 0)
        XCTAssertLessThan(averageRenderMillis, 16)
    }

    func testPublishChurnCompletesAllSurfaceGenerations() {
        let metrics = CompositorStressHarness.simulatePublishChurn()

        XCTAssertEqual(metrics.completedPublishes, metrics.surfaceCount * metrics.cycles)
        XCTAssertEqual(metrics.finalGeneration, UInt64(metrics.cycles))
    }
}
