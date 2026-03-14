import AppKit
import XCTest
@testable import DemoApp

final class InputNormalizerTests: XCTestCase {
    func testPanDeltaUsesPointDifference() {
        XCTAssertEqual(InputNormalizer.panDelta(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 16, y: 8)).width, 6)
        XCTAssertEqual(InputNormalizer.panDelta(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 16, y: 8)).height, -12)
    }

    func testFallbackZoomFactorDirection() {
        XCTAssertGreaterThan(InputNormalizer.fallbackZoomFactor(forScrollDeltaY: -1), 1)
        XCTAssertLessThan(InputNormalizer.fallbackZoomFactor(forScrollDeltaY: 1), 1)
    }

    func testFallbackZoomFactorStaysPositive() {
        XCTAssertGreaterThan(InputNormalizer.fallbackZoomFactor(forScrollDeltaY: -10000), 1)
        XCTAssertGreaterThan(InputNormalizer.fallbackZoomFactor(forScrollDeltaY: 10000), 0)
    }

    func testMagnificationZoomFactorClamps() {
        XCTAssertEqual(InputNormalizer.zoomFactor(forMagnification: 10), 4)
        XCTAssertEqual(InputNormalizer.zoomFactor(forMagnification: -2), 0.25)
    }
}
