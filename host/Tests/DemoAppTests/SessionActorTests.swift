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
        let backend = ReplayLogPTYBackend()
        let actor = try SessionActor(
            sessionID: SessionID(rawValue: "session-1"),
            roomID: RoomID(rawValue: "room-1"),
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            initialSize: TerminalSessionSize(cols: 80, rows: 24),
            backend: backend
        )
        try actor.start()

        backend.emitOutput(Array("screen".utf8))
        let bootstrap = try actor.subscribe(clientID: ClientID(rawValue: "client-1"))
        XCTAssertEqual(bootstrap.outputSeqStart, 1)
        XCTAssertEqual(bootstrap.outputSeqAnchor, 6)
        XCTAssertEqual(String(decoding: bootstrap.bytes, as: UTF8.self), "screen")

        backend.emitOutput(Array("abc".utf8))
        backend.emitOutput(Array("de".utf8))

        XCTAssertEqual(
            actor.outputChunks(),
            [
                SessionOutputChunk(seqStart: 1, seqEnd: 6, bytes: Array("screen".utf8)),
                SessionOutputChunk(seqStart: 7, seqEnd: 9, bytes: Array("abc".utf8)),
                SessionOutputChunk(seqStart: 10, seqEnd: 11, bytes: Array("de".utf8)),
            ]
        )
        XCTAssertEqual(actor.state().outputSeq, 11)
        XCTAssertEqual(
            actor.deliveries(for: ClientID(rawValue: "client-1")),
            [
                .bootstrap(bootstrap),
                .status(SessionStatusRecord(
                    status: .running,
                    outputSeq: 6,
                    exitCode: nil,
                    failureReason: nil,
                    resize: acknowledgedResize(size: TerminalSessionSize(cols: 80, rows: 24))
                )),
                .output(SessionOutputChunk(seqStart: 7, seqEnd: 9, bytes: Array("abc".utf8))),
                .output(SessionOutputChunk(seqStart: 10, seqEnd: 11, bytes: Array("de".utf8))),
            ]
        )
    }

    func testLateJoinBootstrapAndLiveContinuationUseReplayLogBackend() throws {
        let backend = ReplayLogPTYBackend()
        let actor = try SessionActor(
            sessionID: SessionID(rawValue: "session-1"),
            roomID: RoomID(rawValue: "room-1"),
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            initialSize: TerminalSessionSize(cols: 80, rows: 24),
            backend: backend
        )
        try actor.start()

        backend.emitOutput(Array("hello ".utf8))
        backend.emitOutput(Array("world".utf8))

        let bootstrap = try actor.subscribe(clientID: ClientID(rawValue: "late-joiner"))
        XCTAssertEqual(String(decoding: bootstrap.bytes, as: UTF8.self), "hello world")
        XCTAssertEqual(bootstrap.outputSeqStart, 1)
        XCTAssertEqual(bootstrap.outputSeqAnchor, 11)

        backend.emitOutput(Array("!\n".utf8))

        XCTAssertEqual(
            actor.outputChunks(after: bootstrap.outputSeqAnchor),
            [SessionOutputChunk(seqStart: 12, seqEnd: 13, bytes: Array("!\n".utf8))]
        )
    }

    func testBootstrapCarriesCurrentSizeAcrossResizeAndLongRunningOutput() throws {
        let backend = ReplayLogPTYBackend()
        let actor = try SessionActor(
            sessionID: SessionID(rawValue: "session-1"),
            roomID: RoomID(rawValue: "room-1"),
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            initialSize: TerminalSessionSize(cols: 80, rows: 24),
            backend: backend
        )
        try actor.start()

        backend.emitOutput(Array(repeating: UInt8(ascii: "a"), count: 32))
        try actor.resize(to: TerminalSessionSize(cols: 120, rows: 40))
        backend.emitOutput(Array("wrapped-line\nnext-line\n".utf8))

        let bootstrap = try actor.subscribe(clientID: ClientID(rawValue: "client-1"))
        XCTAssertEqual(bootstrap.size, TerminalSessionSize(cols: 120, rows: 40))
        XCTAssertEqual(bootstrap.outputSeqAnchor, 55)
        XCTAssertEqual(
            backend.transcriptLines(),
            [
                "start size=80x24",
                "output bytes=32 text=\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"",
                "resize size=120x40",
                #"output bytes=23 text="wrapped-line\nnext-line\n""#,
            ]
        )
    }

    func testOutputChunksAfterAnchorSlicePartiallyConsumedChunk() throws {
        let backend = ReplayLogPTYBackend()
        let actor = try SessionActor(
            sessionID: SessionID(rawValue: "session-1"),
            roomID: RoomID(rawValue: "room-1"),
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            initialSize: TerminalSessionSize(cols: 80, rows: 24),
            backend: backend
        )
        try actor.start()

        backend.emitOutput(Array("abcdef".utf8))

        XCTAssertEqual(
            actor.outputChunks(after: 3),
            [SessionOutputChunk(seqStart: 4, seqEnd: 6, bytes: Array("def".utf8))]
        )
    }

    func testRevisionedResizeStateMachineTracksDesiredAppliedAcknowledgedAndStaleAcks() throws {
        let backend = TestPTYBackend()
        let actor = try SessionActor(
            sessionID: SessionID(rawValue: "session-1"),
            roomID: RoomID(rawValue: "room-1"),
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            initialSize: TerminalSessionSize(cols: 80, rows: 24),
            backend: backend
        )
        try actor.start()

        let began = try actor.beginAuthoritativeResize(
            to: TerminalSessionSize(cols: 120, rows: 40),
            revision: 4
        )
        XCTAssertEqual(
            began,
            SessionResizeReconciliation(
                revision: 4,
                desiredSize: TerminalSessionSize(cols: 120, rows: 40),
                actualSize: TerminalSessionSize(cols: 80, rows: 24),
                phase: .desired,
                failureReason: nil
            )
        )

        let applied = try actor.applyPendingResize(revision: 4)
        XCTAssertEqual(backend.resizeCalls, [TerminalSessionSize(cols: 120, rows: 40)])
        XCTAssertEqual(
            applied,
            SessionResizeReconciliation(
                revision: 4,
                desiredSize: TerminalSessionSize(cols: 120, rows: 40),
                actualSize: TerminalSessionSize(cols: 120, rows: 40),
                phase: .applied,
                failureReason: nil
            )
        )

        XCTAssertEqual(
            actor.acknowledgePendingResize(revision: 3),
            applied
        )
        XCTAssertEqual(
            actor.acknowledgePendingResize(revision: 4),
            acknowledgedResize(revision: 4, size: TerminalSessionSize(cols: 120, rows: 40))
        )
    }

    func testFailedResizeKeepsDesiredVsActualExplicitUntilRetrySucceeds() throws {
        let backend = TestPTYBackend()
        backend.resizeError = TestFailure(reason: "winsize ioctl failed")
        let actor = try SessionActor(
            sessionID: SessionID(rawValue: "session-1"),
            roomID: RoomID(rawValue: "room-1"),
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            initialSize: TerminalSessionSize(cols: 80, rows: 24),
            backend: backend
        )
        try actor.start()

        _ = try actor.beginAuthoritativeResize(to: TerminalSessionSize(cols: 100, rows: 30), revision: 2)
        XCTAssertThrowsError(try actor.applyPendingResize(revision: 2)) { error in
            XCTAssertEqual(error as? SessionActorError, .backendResizeFailed("winsize ioctl failed"))
        }
        XCTAssertEqual(
            actor.state().resizeReconciliation,
            SessionResizeReconciliation(
                revision: 2,
                desiredSize: TerminalSessionSize(cols: 100, rows: 30),
                actualSize: TerminalSessionSize(cols: 80, rows: 24),
                phase: .failed,
                failureReason: "winsize ioctl failed"
            )
        )

        backend.resizeError = nil
        _ = try actor.beginAuthoritativeResize(to: TerminalSessionSize(cols: 100, rows: 30), revision: 3)
        _ = try actor.applyPendingResize(revision: 3)
        let acknowledged = actor.acknowledgePendingResize(revision: 3)
        XCTAssertEqual(acknowledged, acknowledgedResize(revision: 3, size: TerminalSessionSize(cols: 100, rows: 30)))
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
    var resizeCalls: [TerminalSessionSize] = []

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
        resizeCalls.append(size)
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

private func acknowledgedResize(
    revision: UInt64 = 0,
    size: TerminalSessionSize
) -> SessionResizeReconciliation {
    SessionResizeReconciliation(
        revision: revision,
        desiredSize: size,
        actualSize: size,
        phase: .acknowledged,
        failureReason: nil
    )
}
