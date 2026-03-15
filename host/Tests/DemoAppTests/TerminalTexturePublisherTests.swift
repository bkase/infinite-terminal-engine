import CoreGraphics
import XCTest
@testable import DemoApp

final class TerminalTexturePublisherTests: XCTestCase {
    func testFrontTextureRemainsStableWhilePublishIsInFlight() {
        var state = TerminalTexturePublishState<String>()
        let firstGeneration = state.beginPublish(backTexture: "frame-a", size: CGSize(width: 100, height: 50))
        XCTAssertEqual(firstGeneration, 1)
        XCTAssertNil(state.frontTexture)
        XCTAssertEqual(state.backTexture, "frame-a")
        XCTAssertTrue(state.publishInFlight)

        let blockedGeneration = state.beginPublish(backTexture: "frame-b", size: CGSize(width: 100, height: 50))
        XCTAssertNil(blockedGeneration)
        XCTAssertNil(state.frontTexture)

        XCTAssertTrue(state.completePublish(1))
        XCTAssertEqual(state.frontTexture, "frame-a")
        XCTAssertEqual(state.frontGeneration, 1)
    }

    func testCompletionIncrementsGenerationExactlyOnce() {
        var state = TerminalTexturePublishState<String>()
        XCTAssertEqual(state.beginPublish(backTexture: "frame-a", size: CGSize(width: 80, height: 24)), 1)
        XCTAssertTrue(state.completePublish(1))
        XCTAssertEqual(state.frontGeneration, 1)
        XCTAssertFalse(state.completePublish(1))
        XCTAssertEqual(state.frontGeneration, 1)

        XCTAssertEqual(state.beginPublish(backTexture: "frame-b", size: CGSize(width: 80, height: 24)), 2)
        XCTAssertTrue(state.completePublish(2))
        XCTAssertEqual(state.frontGeneration, 2)
    }

    func testResizeKeepsOldFrontUntilNewSizePublishes() {
        var state = TerminalTexturePublishState<String>()
        XCTAssertEqual(state.beginPublish(backTexture: "front-small", size: CGSize(width: 100, height: 50)), 1)
        XCTAssertTrue(state.completePublish(1))
        XCTAssertEqual(state.frontTexture, "front-small")
        XCTAssertEqual(state.frontSize, CGSize(width: 100, height: 50))

        XCTAssertEqual(state.beginPublish(backTexture: "front-large", size: CGSize(width: 200, height: 100)), 2)
        XCTAssertEqual(state.frontTexture, "front-small")
        XCTAssertEqual(state.frontSize, CGSize(width: 100, height: 50))

        XCTAssertTrue(state.completePublish(2))
        XCTAssertEqual(state.frontTexture, "front-large")
        XCTAssertEqual(state.frontSize, CGSize(width: 200, height: 100))
        XCTAssertEqual(state.frontGeneration, 2)
    }
}
