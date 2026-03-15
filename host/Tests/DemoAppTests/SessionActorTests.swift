import XCTest
@testable import DemoApp

final class SessionActorTests: XCTestCase {
    func testSessionLifecycleCoversProvisioningRunningAndExited() throws {
        let backend = TestPTYBackend()
        let actor = try SessionActor(
            sessionID: SessionID(rawValue: "session-1"),
            roomID: RoomID(rawValue: "room-1"),
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            initialSize: TerminalSessionSize(cols: 80, rows: 24),
            backend: backend
        )

        XCTAssertEqual(actor.state().status, .provisioning)

        try actor.start()
        XCTAssertEqual(actor.state().status, .running)

        backend.emit(.exited(0))
        XCTAssertEqual(actor.state().status, .exited)
        XCTAssertEqual(actor.state().exitCode, 0)
    }

    func testBackendStartFailureTransitionsSessionToFailed() throws {
        let backend = TestPTYBackend()
        backend.startError = TestFailure(reason: "no pty available")
        let actor = try SessionActor(
            sessionID: SessionID(rawValue: "session-1"),
            roomID: RoomID(rawValue: "room-1"),
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            initialSize: TerminalSessionSize(cols: 80, rows: 24),
            backend: backend
        )

        XCTAssertThrowsError(try actor.start()) { error in
            XCTAssertEqual(
                error as? SessionActorError,
                .backendStartFailed("no pty available")
            )
        }
        XCTAssertEqual(actor.state().status, .failed)
        XCTAssertEqual(actor.state().failureReason, "backend_start_failed: no pty available")
    }

    func testOutputSequenceRemainsMonotonicAcrossChunks() throws {
        let backend = TestPTYBackend(bootstrapBytes: Array("screen".utf8))
        let actor = try SessionActor(
            sessionID: SessionID(rawValue: "session-1"),
            roomID: RoomID(rawValue: "room-1"),
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            initialSize: TerminalSessionSize(cols: 80, rows: 24),
            backend: backend
        )
        try actor.start()

        let bootstrap = try actor.subscribe(clientID: ClientID(rawValue: "client-1"))
        XCTAssertEqual(bootstrap.outputSeqAnchor, 0)
        XCTAssertEqual(String(decoding: bootstrap.bytes, as: UTF8.self), "screen")

        backend.emit(.output(Array("abc".utf8)))
        backend.emit(.output(Array("de".utf8)))

        XCTAssertEqual(
            actor.outputChunks(),
            [
                SessionOutputChunk(seqStart: 1, seqEnd: 3, bytes: Array("abc".utf8)),
                SessionOutputChunk(seqStart: 4, seqEnd: 5, bytes: Array("de".utf8)),
            ]
        )
        XCTAssertEqual(actor.state().outputSeq, 5)
        XCTAssertEqual(
            actor.deliveries(for: ClientID(rawValue: "client-1")),
            [
                .bootstrap(bootstrap),
                .status(SessionStatusRecord(status: .running, outputSeq: 0, exitCode: nil, failureReason: nil)),
                .output(SessionOutputChunk(seqStart: 1, seqEnd: 3, bytes: Array("abc".utf8))),
                .output(SessionOutputChunk(seqStart: 4, seqEnd: 5, bytes: Array("de".utf8))),
            ]
        )
    }

    func testSubscriberBookkeepingAndDirectoryLifecycle() throws {
        let directory = SessionDirectory()
        let backend = TestPTYBackend()
        let actor = try directory.provision(
            sessionID: SessionID(rawValue: "session-1"),
            roomID: RoomID(rawValue: "room-1"),
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            initialSize: TerminalSessionSize(cols: 90, rows: 30)
        ) {
            backend
        }

        try actor.start()
        _ = try actor.subscribe(clientID: ClientID(rawValue: "client-1"))
        _ = try actor.subscribe(clientID: ClientID(rawValue: "client-2"))

        XCTAssertEqual(
            actor.state().subscriberIDs,
            [ClientID(rawValue: "client-1"), ClientID(rawValue: "client-2")]
        )
        XCTAssertEqual(directory.activeSessionIDs(), [SessionID(rawValue: "session-1")])

        actor.unsubscribe(clientID: ClientID(rawValue: "client-2"))
        XCTAssertEqual(actor.state().subscriberIDs, [ClientID(rawValue: "client-1")])

        try directory.remove(sessionID: SessionID(rawValue: "session-1"))
        XCTAssertTrue(backend.didStop)
        XCTAssertTrue(directory.activeSessionIDs().isEmpty)
    }

    func testResourceLimitsRejectOversizeAndFailOnBufferedOutputOverflow() throws {
        let backend = TestPTYBackend()
        let limits = SessionResourceLimits(
            maxCols: 100,
            maxRows: 40,
            maxSubscribers: 1,
            maxBufferedOutputBytes: 4
        )

        XCTAssertThrowsError(try SessionActor(
            sessionID: SessionID(rawValue: "session-oversize"),
            roomID: RoomID(rawValue: "room-1"),
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            initialSize: TerminalSessionSize(cols: 120, rows: 24),
            backend: backend,
            resourceLimits: limits
        )) { error in
            XCTAssertEqual(
                error as? SessionActorError,
                .invalidSize(TerminalSessionSize(cols: 120, rows: 24), limits: limits)
            )
        }

        let actor = try SessionActor(
            sessionID: SessionID(rawValue: "session-1"),
            roomID: RoomID(rawValue: "room-1"),
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            initialSize: TerminalSessionSize(cols: 80, rows: 24),
            backend: backend,
            resourceLimits: limits
        )
        try actor.start()
        _ = try actor.subscribe(clientID: ClientID(rawValue: "client-1"))

        XCTAssertThrowsError(try actor.subscribe(clientID: ClientID(rawValue: "client-2"))) { error in
            XCTAssertEqual(error as? SessionActorError, .subscriberLimitExceeded(limit: 1))
        }

        backend.emit(.output(Array("hello".utf8)))
        XCTAssertEqual(actor.state().status, .failed)
        XCTAssertEqual(actor.state().failureReason, "buffered_output_limit_exceeded")
    }
}

private struct TestFailure: Error, LocalizedError {
    let reason: String

    var errorDescription: String? { reason }
}

private final class TestPTYBackend: PTYBackend {
    var eventSink: ((PTYBackendEvent) -> Void)?
    var startError: TestFailure?
    var resizeError: TestFailure?
    var writeError: TestFailure?
    var bootstrapError: TestFailure?
    var bootstrapBytes: [UInt8]
    var didStop = false

    init(bootstrapBytes: [UInt8] = []) {
        self.bootstrapBytes = bootstrapBytes
    }

    func start(sessionID: SessionID, initialSize: TerminalSessionSize) throws {
        if let startError {
            throw startError
        }
    }

    func resize(to size: TerminalSessionSize) throws {
        if let resizeError {
            throw resizeError
        }
    }

    func writeInput(_ bytes: [UInt8]) throws {
        if let writeError {
            throw writeError
        }
    }

    func bootstrap() throws -> [UInt8] {
        if let bootstrapError {
            throw bootstrapError
        }
        return bootstrapBytes
    }

    func stop() throws {
        didStop = true
    }

    func emit(_ event: PTYBackendEvent) {
        eventSink?(event)
    }
}
