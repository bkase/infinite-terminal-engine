import AppKit
import XCTest
@testable import DemoApp

final class InputNormalizerTests: XCTestCase {
    func testFallbackZoomFactorDirection() {
        XCTAssertGreaterThan(InputNormalizer.fallbackZoomFactor(forScrollDeltaY: -1), 1)
        XCTAssertLessThan(InputNormalizer.fallbackZoomFactor(forScrollDeltaY: 1), 1)
    }

    func testMagnificationZoomFactorClamps() {
        XCTAssertEqual(InputNormalizer.zoomFactor(forMagnification: 10), 4)
        XCTAssertEqual(InputNormalizer.zoomFactor(forMagnification: -2), 0.25)
    }
}
