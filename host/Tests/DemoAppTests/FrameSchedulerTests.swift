import XCTest
@testable import DemoApp

final class FrameSchedulerTests: XCTestCase {
    func testCameraChangeSchedulesSingleDraw() {
        var scheduler = FrameScheduler()

        XCTAssertTrue(scheduler.invalidate(.camera))
        XCTAssertFalse(scheduler.invalidate(.camera))
        XCTAssertEqual(scheduler.consumePendingDraw(), .camera)
    }

    func testTexturePublishAndTimerCoalesce() {
        var scheduler = FrameScheduler()

        XCTAssertTrue(scheduler.invalidate(.texture))
        XCTAssertFalse(scheduler.invalidate(.timer))
        XCTAssertEqual(scheduler.consumePendingDraw(), [.texture, .timer])
    }

    func testIdleSchedulerDoesNotDraw() {
        var scheduler = FrameScheduler()
        XCTAssertNil(scheduler.consumePendingDraw())
    }
}
