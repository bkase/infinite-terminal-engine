import XCTest

@testable import DemoApp

final class TextureBudgetPolicyTests: XCTestCase {
    func testTextureSizeUsesCanonicalFormula() throws {
        let profile = try RenderProfileCatalog.defaultProfile()
        XCTAssertEqual(
            TextureBudgetPolicy.pixelSize(cols: 80, rows: 24, profile: profile, backingScale: 2),
            CGSize(width: 1160, height: 864)
        )
    }

    func testEstimatedBytesUseFrontAndBackBuffersWithoutMipmaps() {
        XCTAssertEqual(
            TextureBudgetPolicy.estimatedBytes(pixelSize: CGSize(width: 1280, height: 800)),
            8_192_000
        )
    }

    func testRoomBudgetFlagsOversizedAndOverBudgetStates() throws {
        let profile = try RenderProfileCatalog.defaultProfile()
        var store = SurfaceStore()
        store.replaceAll(with: (0..<50).map { index in
            TerminalSurface(
                id: TerminalSurfaceID("surface-\(index)"),
                sessionID: "session-\(index)",
                origin: .zero,
                cols: 120,
                rows: 50,
                profileID: profile.id,
                stackRank: index,
                flags: [.acceptsInput]
            )
        })

        let report = TextureBudgetPolicy.assessRoom(
            surfaces: store,
            profilesByID: [profile.id: profile],
            backingScale: 2
        )

        XCTAssertTrue(report.exceedsRoomBudget)
        XCTAssertFalse(report.oversizedSurfaceIDs.isEmpty)
    }
}
