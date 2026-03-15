import XCTest
@testable import DemoApp

final class FrameSchedulerTests: XCTestCase {
    func testCameraChangeSchedulesSingleDraw() {
        var scheduler = FrameScheduler()

        XCTAssertTrue(scheduler.invalidate(.camera))
        XCTAssertFalse(scheduler.invalidate(.camera))
        XCTAssertEqual(scheduler.pendingDraw(), .camera)
        XCTAssertEqual(scheduler.completePendingDraw(), .camera)
    }

    func testTexturePublishAndTimerCoalesce() {
        var scheduler = FrameScheduler()

        XCTAssertTrue(scheduler.invalidate(.texture))
        XCTAssertFalse(scheduler.invalidate(.timer))
        XCTAssertEqual(scheduler.pendingDraw(), [.texture, .timer])
        XCTAssertEqual(scheduler.completePendingDraw(), [.texture, .timer])
    }

    func testIdleSchedulerDoesNotDraw() {
        var scheduler = FrameScheduler()
        XCTAssertNil(scheduler.pendingDraw())
        XCTAssertNil(scheduler.completePendingDraw())
    }

    func testPendingDrawSurvivesFailedAttemptUntilCompleted() {
        var scheduler = FrameScheduler()

        XCTAssertTrue(scheduler.invalidate([.texture, .timer]))
        XCTAssertEqual(scheduler.pendingDraw(), [.texture, .timer])
        XCTAssertEqual(scheduler.pendingDraw(), [.texture, .timer])
        XCTAssertTrue(scheduler.scheduled)

        XCTAssertEqual(scheduler.completePendingDraw(), [.texture, .timer])
        XCTAssertNil(scheduler.pendingDraw())
        XCTAssertFalse(scheduler.scheduled)
    }
}
