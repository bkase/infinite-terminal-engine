import XCTest
@testable import DemoApp

final class RenderProfileTests: XCTestCase {
    func testLoadAllProfiles() throws {
        let profiles = try RenderProfileCatalog.load()
        XCTAssertEqual(profiles.map(\.id), ["collab-pragmata-v1"])
    }

    func testDefaultProfileSurfaceSizeIsDeterministic() throws {
        let profile = try RenderProfileCatalog.defaultProfile()
        XCTAssertEqual(
            profile.surfacePixelSize(cols: 80, rows: 24, backingScale: 2),
            CGSize(width: 1160, height: 864)
        )
    }

    func testMetricValidationRejectsDrift() throws {
        let profile = try XCTUnwrap(try RenderProfileCatalog.load().first)
        let drifted = RenderProfile(
            id: profile.id,
            themeID: profile.themeID,
            pointSize: profile.pointSize,
            cellWidth: profile.cellWidth + 1,
            lineHeight: profile.lineHeight,
            paddingX: profile.paddingX,
            paddingY: profile.paddingY,
            titlebarHeight: profile.titlebarHeight,
            regularFontFile: profile.regularFontFile,
            boldFontFile: profile.boldFontFile,
            italicFontFile: profile.italicFontFile
        )

        XCTAssertThrowsError(try drifted.validate(in: .module)) { error in
            guard case RenderProfileError.metricDrift = error else {
                XCTFail("expected metric drift error, got \(error)")
                return
            }
        }
    }
}
