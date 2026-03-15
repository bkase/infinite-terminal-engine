import XCTest
@testable import DemoApp

final class SessionResizeCoordinatorTests: XCTestCase {
    func testRepeatedAuthoritativeResizeIsIdempotent() throws {
        let fixture = try makeFixture()

        let first = try fixture.gateway.submit(fixture.record(
            opID: "resize-1",
            payload: .resizeSurface(ResizeSurfaceOp(
                surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
                cols: 120,
                rows: 40
            ))
        ), from: ClientID(rawValue: "client-1"))
        fixture.coordinator.apply(first)

        let second = try fixture.gateway.submit(fixture.record(
            opID: "resize-2",
            payload: .resizeSurface(ResizeSurfaceOp(
                surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
                cols: 120,
                rows: 40
            ))
        ), from: ClientID(rawValue: "client-1"))
        fixture.coordinator.apply(second)

        XCTAssertEqual(
            fixture.backend.transcript.filter {
                if case .resize = $0 { return true }
                return false
            }.count,
            1
        )
        XCTAssertEqual(
            fixture.session.state().resizeReconciliation,
            SessionResizeReconciliation(
                revision: 4,
                desiredSize: TerminalSessionSize(cols: 120, rows: 40),
                actualSize: TerminalSessionSize(cols: 120, rows: 40),
                phase: .acknowledged,
                failureReason: nil
            )
        )
    }

    func testLaggingAcknowledgementLeavesClientVisibleAppliedState() throws {
        let fixture = try makeFixture(automaticallyAcknowledgeResizes: false)
        let applied = try fixture.gateway.submit(fixture.record(
            opID: "resize-1",
            payload: .resizeSurface(ResizeSurfaceOp(
                surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
                cols: 100,
                rows: 30
            ))
        ), from: ClientID(rawValue: "client-1"))

        fixture.coordinator.apply(applied)

        XCTAssertEqual(
            fixture.session.state().resizeReconciliation,
            SessionResizeReconciliation(
                revision: 3,
                desiredSize: TerminalSessionSize(cols: 100, rows: 30),
                actualSize: TerminalSessionSize(cols: 100, rows: 30),
                phase: .applied,
                failureReason: nil
            )
        )
        XCTAssertTrue(
            fixture.coordinator.logLines(for: SessionID(rawValue: "session-1")).contains {
                $0.contains("action=ui_lag")
            }
        )

        fixture.coordinator.acknowledge(sessionID: SessionID(rawValue: "session-1"))
        XCTAssertEqual(
            fixture.session.state().resizeReconciliation,
            SessionResizeReconciliation(
                revision: 3,
                desiredSize: TerminalSessionSize(cols: 100, rows: 30),
                actualSize: TerminalSessionSize(cols: 100, rows: 30),
                phase: .acknowledged,
                failureReason: nil
            )
        )
    }

    func testFailedResizeCanRetryAndReconnectReconcilesAuthoritativeSize() throws {
        let fixture = try makeFixture()
        fixture.backend.failResize(reason: "pty offline")

        let failed = try fixture.gateway.submit(fixture.record(
            opID: "resize-1",
            payload: .resizeSurface(ResizeSurfaceOp(
                surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
                cols: 132,
                rows: 50
            ))
        ), from: ClientID(rawValue: "client-1"))
        fixture.coordinator.apply(failed)

        XCTAssertEqual(
            fixture.session.state().resizeReconciliation,
            SessionResizeReconciliation(
                revision: 3,
                desiredSize: TerminalSessionSize(cols: 132, rows: 50),
                actualSize: TerminalSessionSize(cols: 80, rows: 24),
                phase: .failed,
                failureReason: "pty offline"
            )
        )

        fixture.backend.clearResizeFailure()
        fixture.coordinator.retry(sessionID: SessionID(rawValue: "session-1"))
        XCTAssertEqual(
            fixture.session.state().resizeReconciliation,
            SessionResizeReconciliation(
                revision: 3,
                desiredSize: TerminalSessionSize(cols: 132, rows: 50),
                actualSize: TerminalSessionSize(cols: 132, rows: 50),
                phase: .acknowledged,
                failureReason: nil
            )
        )

        let reconnectSnapshot = fixture.actor.snapshot
        fixture.coordinator.reconcile(snapshot: reconnectSnapshot)
        XCTAssertEqual(
            fixture.session.state().resizeReconciliation,
            SessionResizeReconciliation(
                revision: reconnectSnapshot.roomSeq,
                desiredSize: TerminalSessionSize(cols: 132, rows: 50),
                actualSize: TerminalSessionSize(cols: 132, rows: 50),
                phase: .acknowledged,
                failureReason: nil
            )
        )
    }

    private func makeFixture(
        automaticallyAcknowledgeResizes: Bool = true
    ) throws -> SessionResizeFixture {
        let journal = InMemoryRoomJournalStore()
        let snapshots = InMemoryRoomSnapshotStore()
        let actor = RoomActor(
            snapshot: DurableRoomSnapshot(
                schemaVersion: .v1,
                roomID: RoomID(rawValue: "room-1"),
                roomSeq: 0,
                renderProfileIDs: ["profile"],
                surfaces: [],
                controlLeases: []
            ),
            journalStore: journal,
            snapshotStore: snapshots
        )
        let gateway = RoomGateway(actor: actor, journalStore: journal, snapshotStore: snapshots)
        let directory = SessionDirectory()
        let backend = ReplayLogPTYBackend()
        let session = try directory.provision(
            sessionID: SessionID(rawValue: "session-1"),
            roomID: RoomID(rawValue: "room-1"),
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            initialSize: TerminalSessionSize(cols: 80, rows: 24)
        ) {
            backend
        }
        try session.start()
        let coordinator = SessionResizeCoordinator(
            directory: directory,
            automaticallyAcknowledgeResizes: automaticallyAcknowledgeResizes
        )

        _ = try gateway.submit(record(opID: "create-1", payload: .createSurface(CreateSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            xWorld: 0,
            yWorld: 0,
            cols: 80,
            rows: 24,
            profileID: "profile",
            terminalTemplate: nil
        ))), from: ClientID(rawValue: "client-1"))
        _ = try gateway.submit(record(opID: "attach-1", payload: .attachSession(AttachSessionOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            sessionID: SessionID(rawValue: "session-1")
        ))), from: ClientID(rawValue: "client-1"))

        return SessionResizeFixture(
            actor: actor,
            gateway: gateway,
            session: session,
            backend: backend,
            coordinator: coordinator
        )
    }

    private func record(opID: String, payload: RoomOperationPayload) -> RoomOpRecord {
        RoomOpRecord(
            schemaVersion: .v1,
            roomID: RoomID(rawValue: "room-1"),
            roomSeq: nil,
            opID: RoomOpID(rawValue: opID),
            clientID: ClientID(rawValue: "client-1"),
            submittedAtMillis: 100,
            payload: payload
        )
    }
}

private struct SessionResizeFixture {
    let actor: RoomActor
    let gateway: RoomGateway
    let session: SessionActor
    let backend: ReplayLogPTYBackend
    let coordinator: SessionResizeCoordinator

    func record(opID: String, payload: RoomOperationPayload) -> RoomOpRecord {
        RoomOpRecord(
            schemaVersion: .v1,
            roomID: RoomID(rawValue: "room-1"),
            roomSeq: nil,
            opID: RoomOpID(rawValue: opID),
            clientID: ClientID(rawValue: "client-1"),
            submittedAtMillis: 100,
            payload: payload
        )
    }
}

private extension ReplayLogPTYBackend {
    func failResize(reason: String) {
        resizeFailureReason = reason
    }

    func clearResizeFailure() {
        resizeFailureReason = nil
    }
}
