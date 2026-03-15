import XCTest
@testable import DemoApp

final class RoomActorTests: XCTestCase {
    func testSetStackRankRewritesDenseRanksDeterministically() throws {
        let actor = makeActor()

        for (index, surfaceID) in ["surface-1", "surface-2", "surface-3"].enumerated() {
            _ = try actor.apply(record(opID: "create-\(index)", payload: .createSurface(CreateSurfaceOp(
                surfaceID: TerminalSurfaceID(rawValue: surfaceID),
                xWorld: Double(index * 10),
                yWorld: Double(index * 10),
                cols: 80,
                rows: 24,
                profileID: "profile",
                terminalTemplate: nil
            ))))
        }

        _ = try actor.apply(record(opID: "reorder-1", payload: .setStackRank(SetStackRankOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-3"),
            targetRank: 0
        ))))
        _ = try actor.apply(record(opID: "reorder-2", payload: .setStackRank(SetStackRankOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            targetRank: 99
        ))))

        XCTAssertEqual(
            actor.snapshot.surfaces.map(\.id.rawValue),
            ["surface-3", "surface-2", "surface-1"]
        )
        XCTAssertEqual(actor.snapshot.surfaces.map(\.stackRank), [0, 1, 2])
    }

    func testCloseSurfaceRewritesDenseRanks() throws {
        let actor = makeActor()

        for (index, surfaceID) in ["surface-1", "surface-2", "surface-3"].enumerated() {
            _ = try actor.apply(record(opID: "create-\(index)", payload: .createSurface(CreateSurfaceOp(
                surfaceID: TerminalSurfaceID(rawValue: surfaceID),
                xWorld: Double(index * 10),
                yWorld: Double(index * 10),
                cols: 80,
                rows: 24,
                profileID: "profile",
                terminalTemplate: nil
            ))))
        }

        _ = try actor.apply(record(opID: "close-middle", payload: .closeSurface(CloseSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-2")
        ))))

        XCTAssertEqual(
            actor.snapshot.surfaces.map(\.id.rawValue),
            ["surface-1", "surface-3"]
        )
        XCTAssertEqual(actor.snapshot.surfaces.map(\.stackRank), [0, 1])
    }

    func testCreateSurfaceRejectsUnknownProfileID() throws {
        let actor = makeActor()

        XCTAssertThrowsError(try actor.apply(record(opID: "create-bad-profile", payload: .createSurface(CreateSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            xWorld: 0,
            yWorld: 0,
            cols: 80,
            rows: 24,
            profileID: "missing-profile",
            terminalTemplate: nil
        ))))) { error in
            XCTAssertEqual(error as? RoomActorError, .unknownProfileID("missing-profile"))
        }
    }

    func testResizeRejectsNonPositiveDimensions() throws {
        let actor = makeActor()
        _ = try actor.apply(record(opID: "create-1", payload: .createSurface(CreateSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            xWorld: 0,
            yWorld: 0,
            cols: 80,
            rows: 24,
            profileID: "profile",
            terminalTemplate: nil
        ))))

        XCTAssertThrowsError(try actor.apply(record(opID: "resize-zero-cols", payload: .resizeSurface(ResizeSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            cols: 0,
            rows: 24
        ))))) { error in
            XCTAssertEqual(error as? RoomSchemaValidationError, .nonPositiveDimension("cols"))
        }
    }

    func testAttachAndDetachSessionTransitionsAreValidated() throws {
        let actor = makeActor()
        _ = try actor.apply(record(opID: "create-1", payload: .createSurface(CreateSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            xWorld: 0,
            yWorld: 0,
            cols: 80,
            rows: 24,
            profileID: "profile",
            terminalTemplate: nil
        ))))
        _ = try actor.apply(record(opID: "attach-1", payload: .attachSession(AttachSessionOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            sessionID: SessionID(rawValue: "session-1")
        ))))

        XCTAssertThrowsError(try actor.apply(record(opID: "attach-2", payload: .attachSession(AttachSessionOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            sessionID: SessionID(rawValue: "session-2")
        ))))) { error in
            XCTAssertEqual(
                error as? RoomActorError,
                .sessionAlreadyAttached(TerminalSurfaceID(rawValue: "surface-1"))
            )
        }

        _ = try actor.apply(record(opID: "detach-1", payload: .detachSession(DetachSessionOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1")
        ))))

        XCTAssertThrowsError(try actor.apply(record(opID: "detach-2", payload: .detachSession(DetachSessionOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1")
        ))))) { error in
            XCTAssertEqual(
                error as? RoomActorError,
                .noSessionAttached(TerminalSurfaceID(rawValue: "surface-1"))
            )
        }
    }

    func testAttachSessionRejectsSessionAlreadyAttachedElsewhere() throws {
        let actor = makeActor()
        _ = try actor.apply(record(opID: "create-1", payload: .createSurface(CreateSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            xWorld: 0,
            yWorld: 0,
            cols: 80,
            rows: 24,
            profileID: "profile",
            terminalTemplate: nil
        ))))
        _ = try actor.apply(record(opID: "create-2", payload: .createSurface(CreateSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-2"),
            xWorld: 20,
            yWorld: 20,
            cols: 80,
            rows: 24,
            profileID: "profile",
            terminalTemplate: nil
        ))))
        _ = try actor.apply(record(opID: "attach-1", payload: .attachSession(AttachSessionOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            sessionID: SessionID(rawValue: "session-1")
        ))))

        XCTAssertThrowsError(try actor.apply(record(opID: "attach-2", payload: .attachSession(AttachSessionOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-2"),
            sessionID: SessionID(rawValue: "session-1")
        ))))) { error in
            XCTAssertEqual(
                error as? RoomActorError,
                .sessionAttachedElsewhere(SessionID(rawValue: "session-1"))
            )
        }
    }

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

    func testRecoveryRestoresLeaseStateFromSnapshotBoundary() throws {
        let journal = InMemoryRoomJournalStore()
        let snapshots = InMemoryRoomSnapshotStore()
        let actor = RoomActor(
            snapshot: emptySnapshot(),
            journalStore: journal,
            snapshotStore: snapshots,
            snapshotInterval: 3
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
        _ = try actor.apply(record(opID: "op-2", payload: .attachSession(AttachSessionOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            sessionID: SessionID(rawValue: "session-1")
        ))))
        _ = try actor.apply(record(opID: "op-3", payload: .acquireControl(AcquireControlOp(
            sessionID: SessionID(rawValue: "session-1"),
            holderUserID: UserID(rawValue: "user-1")
        ))))

        let recovered = try RoomActor.recover(
            roomID: RoomID(rawValue: "room-1"),
            journalStore: journal,
            snapshotStore: snapshots,
            snapshotInterval: 3
        )

        XCTAssertEqual(recovered.snapshot.controlLeases, actor.snapshot.controlLeases)
        XCTAssertEqual(
            recovered.controlLease(for: SessionID(rawValue: "session-1")),
            actor.controlLease(for: SessionID(rawValue: "session-1"))
        )
    }

    func testLeaseEpochRemainsMonotonicAcrossSnapshotRecovery() throws {
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
        _ = try actor.apply(record(opID: "op-2", payload: .attachSession(AttachSessionOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            sessionID: SessionID(rawValue: "session-1")
        ))))
        _ = try actor.apply(record(opID: "op-3", payload: .acquireControl(AcquireControlOp(
            sessionID: SessionID(rawValue: "session-1"),
            holderUserID: UserID(rawValue: "user-1")
        ))))

        let recovered = try RoomActor.recover(
            roomID: RoomID(rawValue: "room-1"),
            journalStore: journal,
            snapshotStore: snapshots,
            snapshotInterval: 2
        )

        XCTAssertEqual(recovered.controlLease(for: SessionID(rawValue: "session-1"))?.leaseEpoch, 1)

        _ = try recovered.apply(record(opID: "op-4", payload: .releaseControl(ReleaseControlOp(
            sessionID: SessionID(rawValue: "session-1")
        ))))
        _ = try recovered.apply(record(opID: "op-5", payload: .acquireControl(AcquireControlOp(
            sessionID: SessionID(rawValue: "session-1"),
            holderUserID: UserID(rawValue: "user-2")
        ))))

        XCTAssertEqual(recovered.controlLease(for: SessionID(rawValue: "session-1"))?.leaseEpoch, 2)
    }

    func testCompetingLeaseAcquireIsRejectedWhileCurrentHolderKeepsLease() throws {
        let actor = makeActor(snapshotInterval: 10)

        _ = try actor.apply(record(opID: "op-1", payload: .createSurface(CreateSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            xWorld: 0,
            yWorld: 0,
            cols: 80,
            rows: 24,
            profileID: "profile",
            terminalTemplate: nil
        ))))
        _ = try actor.apply(record(opID: "op-2", payload: .attachSession(AttachSessionOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            sessionID: SessionID(rawValue: "session-1")
        ))))
        _ = try actor.apply(record(opID: "op-3", payload: .acquireControl(AcquireControlOp(
            sessionID: SessionID(rawValue: "session-1"),
            holderUserID: UserID(rawValue: "user-1")
        ))))

        XCTAssertThrowsError(try actor.apply(record(opID: "op-4", payload: .acquireControl(AcquireControlOp(
            sessionID: SessionID(rawValue: "session-1"),
            holderUserID: UserID(rawValue: "user-2")
        ))))) { error in
            XCTAssertEqual(
                error as? RoomActorError,
                .controlLeaseHeldByAnotherUser(
                    SessionID(rawValue: "session-1"),
                    holderUserID: UserID(rawValue: "user-1")
                )
            )
        }

        XCTAssertEqual(actor.controlLease(for: SessionID(rawValue: "session-1"))?.holderUserID, UserID(rawValue: "user-1"))
        XCTAssertEqual(actor.controlLease(for: SessionID(rawValue: "session-1"))?.leaseEpoch, 1)
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
            surfaces: [],
            controlLeases: []
        )
    }

    private func makeActor(snapshotInterval: UInt64 = 100) -> RoomActor {
        RoomActor(
            snapshot: emptySnapshot(),
            journalStore: InMemoryRoomJournalStore(),
            snapshotStore: InMemoryRoomSnapshotStore(),
            snapshotInterval: snapshotInterval
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
