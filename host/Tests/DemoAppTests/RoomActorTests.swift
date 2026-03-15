import XCTest
@testable import DemoApp

final class RoomActorTests: XCTestCase {
    func testRoomSeqIsMonotonicAcrossAcceptedOps() throws {
        let journal = InMemoryRoomJournalStore()
        let snapshots = InMemoryRoomSnapshotStore()
        let actor = RoomActor(
            snapshot: emptySnapshot(),
            journalStore: journal,
            snapshotStore: snapshots,
            snapshotInterval: 100
        )

        let create = try actor.apply(record(opID: "op-1", payload: .createSurface(CreateSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            xWorld: 0,
            yWorld: 0,
            cols: 80,
            rows: 24,
            profileID: "profile",
            terminalTemplate: nil
        ))))
        let move = try actor.apply(record(opID: "op-2", payload: .moveSurface(MoveSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            xWorld: 24,
            yWorld: 40
        ))))

        XCTAssertEqual(create.record.roomSeq, 1)
        XCTAssertEqual(move.record.roomSeq, 2)
        XCTAssertEqual(actor.snapshot.roomSeq, 2)
    }

    func testSnapshotReplayMatchesUninterruptedExecution() throws {
        let journal = InMemoryRoomJournalStore()
        let snapshots = InMemoryRoomSnapshotStore()
        let actor = RoomActor(
            snapshot: emptySnapshot(),
            journalStore: journal,
            snapshotStore: snapshots,
            snapshotInterval: 2
        )

        _ = try actor.apply(record(opID: "op-1", payload: .createSurface(CreateSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            xWorld: 10,
            yWorld: 20,
            cols: 80,
            rows: 24,
            profileID: "profile",
            terminalTemplate: nil
        ))))
        _ = try actor.apply(record(opID: "op-2", payload: .attachSession(AttachSessionOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            sessionID: SessionID(rawValue: "session-1")
        ))))
        _ = try actor.apply(record(opID: "op-3", payload: .setSurfaceTitle(SetSurfaceTitleOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            title: "shell"
        ))))

        let recovered = try RoomActor.recover(
            roomID: RoomID(rawValue: "room-1"),
            journalStore: journal,
            snapshotStore: snapshots,
            snapshotInterval: 2
        )

        XCTAssertEqual(recovered.snapshot, actor.snapshot)
    }

    func testRecoveryReplaysJournalTailAfterSnapshot() throws {
        let journal = InMemoryRoomJournalStore()
        let snapshots = InMemoryRoomSnapshotStore()
        let actor = RoomActor(
            snapshot: emptySnapshot(),
            journalStore: journal,
            snapshotStore: snapshots,
            snapshotInterval: 2
        )

        _ = try actor.apply(record(opID: "op-1", payload: .createSurface(CreateSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            xWorld: 0,
            yWorld: 0,
            cols: 80,
            rows: 24,
            profileID: "profile",
            terminalTemplate: nil
        ))))
        _ = try actor.apply(record(opID: "op-2", payload: .moveSurface(MoveSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            xWorld: 10,
            yWorld: 10
        ))))
        _ = try actor.apply(record(opID: "op-3", payload: .resizeSurface(ResizeSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            cols: 120,
            rows: 40
        ))))

        let recovered = try RoomActor.recover(
            roomID: RoomID(rawValue: "room-1"),
            journalStore: journal,
            snapshotStore: snapshots,
            snapshotInterval: 2
        )

        XCTAssertEqual(recovered.snapshot.roomSeq, 3)
        XCTAssertEqual(recovered.snapshot.surfaces.first?.cols, 120)
        XCTAssertEqual(recovered.snapshot.surfaces.first?.rows, 40)
    }

    func testDuplicateOpIDIsIdempotent() throws {
        let journal = InMemoryRoomJournalStore()
        let snapshots = InMemoryRoomSnapshotStore()
        let actor = RoomActor(
            snapshot: emptySnapshot(),
            journalStore: journal,
            snapshotStore: snapshots,
            snapshotInterval: 100
        )

        let first = try actor.apply(record(opID: "op-1", payload: .createSurface(CreateSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            xWorld: 0,
            yWorld: 0,
            cols: 80,
            rows: 24,
            profileID: "profile",
            terminalTemplate: nil
        ))))
        let duplicate = try actor.apply(record(opID: "op-1", payload: .createSurface(CreateSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-2"),
            xWorld: 20,
            yWorld: 20,
            cols: 90,
            rows: 30,
            profileID: "profile",
            terminalTemplate: nil
        ))))

        XCTAssertFalse(first.wasDuplicate)
        XCTAssertTrue(duplicate.wasDuplicate)
        XCTAssertEqual(actor.snapshot.surfaces.count, 1)
        XCTAssertEqual(duplicate.record.roomSeq, 1)
    }

    private func emptySnapshot() -> DurableRoomSnapshot {
        DurableRoomSnapshot(
            schemaVersion: .v1,
            roomID: RoomID(rawValue: "room-1"),
            roomSeq: 0,
            renderProfileIDs: ["profile"],
            surfaces: []
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
