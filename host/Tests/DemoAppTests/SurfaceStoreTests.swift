import CoreGraphics
import XCTest

@testable import DemoApp

final class SurfaceStoreTests: XCTestCase {
    func testUpsertUpdateAndRemoveSurface() throws {
        var store = SurfaceStore()
        let alpha = makeSurface(id: "alpha", stackRank: 0, cols: 80, rows: 24)
        store.upsert(alpha)

        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(store.surface(id: alpha.id), alpha)

        var updated = alpha
        updated.origin = CGPoint(x: 128, y: 64)
        updated.stackRank = 3
        store.upsert(updated)

        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(store.surface(id: alpha.id), updated)

        let removed = store.remove(alpha.id)
        XCTAssertEqual(removed, updated)
        XCTAssertTrue(store.isEmpty)
    }

    func testGeometryDerivesOuterFrameAndContentFromProfile() throws {
        let profile = try RenderProfileCatalog.defaultProfile()
        let surface = makeSurface(
            id: "alpha",
            stackRank: 0,
            origin: CGPoint(x: 24, y: 40),
            cols: 80,
            rows: 24,
            profileID: profile.id
        )

        let geometry = try XCTUnwrap(
            SurfaceStore.geometry(
                for: surface,
                profilesByID: [profile.id: profile],
                backingScale: 2
            )
        )

        XCTAssertEqual(geometry.frame.origin, CGPoint(x: 24, y: 40))
        XCTAssertEqual(geometry.frame.size, profile.surfaceLogicalSize(cols: 80, rows: 24))
        XCTAssertEqual(geometry.contentFrame.origin.x, 24 + profile.paddingX)
        XCTAssertEqual(geometry.contentFrame.origin.y, 40 + profile.titlebarHeight + profile.paddingY)
        XCTAssertEqual(geometry.contentFrame.size.width, CGFloat(80) * profile.cellWidth)
        XCTAssertEqual(geometry.contentFrame.size.height, CGFloat(24) * profile.lineHeight)
        XCTAssertEqual(geometry.titlebarFrame.height, profile.titlebarHeight)
        XCTAssertEqual(geometry.pixelSize, profile.surfacePixelSize(cols: 80, rows: 24, backingScale: 2))
    }

    func testOrderedSurfaceIDsStayDenseWhenStackRanksChange() {
        var store = SurfaceStore()
        store.upsert(makeSurface(id: "gamma", stackRank: 2))
        store.upsert(makeSurface(id: "alpha", stackRank: 0))
        store.upsert(makeSurface(id: "beta", stackRank: 1))

        XCTAssertEqual(store.orderedSurfaceIDs(), [
            TerminalSurfaceID("alpha"),
            TerminalSurfaceID("beta"),
            TerminalSurfaceID("gamma"),
        ])

        store.upsert(makeSurface(id: "alpha", stackRank: 4))
        store.upsert(makeSurface(id: "beta", stackRank: -1))

        XCTAssertEqual(store.orderedSurfaceIDs(), [
            TerminalSurfaceID("beta"),
            TerminalSurfaceID("gamma"),
            TerminalSurfaceID("alpha"),
        ])
    }

    private func makeSurface(
        id: String,
        stackRank: Int,
        origin: CGPoint = .zero,
        cols: Int = 80,
        rows: Int = 24,
        profileID: String = RenderProfileCatalog.defaultProfileID
    ) -> TerminalSurface {
        TerminalSurface(
            id: TerminalSurfaceID(id),
            sessionID: "session-\(id)",
            origin: origin,
            cols: cols,
            rows: rows,
            profileID: profileID,
            stackRank: stackRank,
            flags: [.acceptsInput]
        )
    }
}
