import AppKit
import Carbon.HIToolbox
import GhosttyKit
import XCTest
@testable import DemoApp

final class InputNormalizerTests: XCTestCase {
    func testNormalizedKeyInputMapsPrintableA() {
        let input = InputNormalizer.normalizedKeyInput(
            keyCode: kVK_ANSI_A,
            characters: "a",
            charactersIgnoringModifiers: "a",
            modifierFlags: [],
            isRepeat: false
        )

        XCTAssertEqual(input?.keyCode, UInt16(GHOSTTY_KEY_A.rawValue))
        XCTAssertEqual(input?.text, "a")
        XCTAssertEqual(input?.action, GhosttyKeyActionCode.press)
    }

    func testNormalizedKeyInputMapsSpecialKeys() {
        let input = InputNormalizer.normalizedKeyInput(
            keyCode: kVK_Return,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            modifierFlags: [.shift, .command],
            isRepeat: true
        )

        XCTAssertEqual(input?.keyCode, UInt16(GHOSTTY_KEY_ENTER.rawValue))
        XCTAssertEqual(input?.mods, UInt16(GHOSTTY_MODS_SHIFT.rawValue | GHOSTTY_MODS_SUPER.rawValue))
        XCTAssertEqual(input?.action, GhosttyKeyActionCode.repeatPress)
    }

    @MainActor
    func testEncodedKeyBytesComeFromGhosttyEncoder() {
        let input = GhosttyKeyInput(
            action: GhosttyKeyActionCode.press,
            mods: 0,
            consumedMods: 0,
            keyCode: UInt16(GHOSTTY_KEY_ENTER.rawValue),
            text: "\r",
            unshiftedCodepoint: 13,
            composing: false
        )

        XCTAssertEqual(GhosttySurfaceAdapter.encodeKeyBytes(input), Data("\r".utf8))
    }

    func testBracketedPasteWrapsPayload() {
        XCTAssertEqual(
            InputNormalizer.encodedPasteBytes(for: "echo 1\n", bracketed: true),
            Data("\u{1b}[200~echo 1\n\u{1b}[201~".utf8)
        )
    }

    func testUnbracketedPasteNormalizesNewlinesAndStripsEndMarker() {
        XCTAssertEqual(
            InputNormalizer.encodedPasteBytes(for: "a\n\u{1b}[201~b", bracketed: false),
            Data("a\rb".utf8)
        )
    }

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
