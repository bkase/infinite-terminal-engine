import XCTest
@testable import DemoApp

final class RoomGatewayTests: XCTestCase {
    func testColdJoinReturnsAuthoritativeSnapshot() throws {
        let fixture = try makeFixture(snapshotInterval: 10)
        _ = try applyStandardOps(with: fixture.gateway)

        let response = try fixture.gateway.connect(clientID: ClientID(rawValue: "client-cold"), knownRoomSeq: nil)

        XCTAssertEqual(response.mode, .coldJoin)
        XCTAssertEqual(response.baseSnapshot, fixture.actor.snapshot)
        XCTAssertEqual(response.tailRecords, [])
        XCTAssertEqual(try response.reconstructReplica(existingSnapshot: nil), fixture.actor.snapshot)
    }

    func testTailReplayFromKnownRoomSeqRebuildsReplica() throws {
        let fixture = try makeFixture(snapshotInterval: 10)
        let records = try applyStandardOps(with: fixture.gateway)

        let localSnapshot = try RoomStateReducer.replay(
            snapshot: emptySnapshot(),
            records: Array(records.prefix(1))
        )
        let response = try fixture.gateway.connect(clientID: ClientID(rawValue: "client-tail"), knownRoomSeq: 1)

        XCTAssertEqual(response.mode, .tailOnly)
        XCTAssertNil(response.baseSnapshot)
        XCTAssertEqual(response.tailRecords.map(\.roomSeq), [2, 3])
        XCTAssertEqual(try response.reconstructReplica(existingSnapshot: localSnapshot), fixture.actor.snapshot)
    }

    func testReconnectFallsBackToSnapshotAndTailAfterGap() throws {
        let fixture = try makeFixture(snapshotInterval: 2)
        _ = try fixture.gateway.submit(record(opID: "op-1", payload: .createSurface(CreateSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            xWorld: 0,
            yWorld: 0,
            cols: 80,
            rows: 24,
            profileID: "profile",
            terminalTemplate: nil
        ))), from: ClientID(rawValue: "client-1"))
        _ = try fixture.gateway.submit(record(opID: "op-2", payload: .moveSurface(MoveSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            xWorld: 10,
            yWorld: 12
        ))), from: ClientID(rawValue: "client-1"))
        _ = try fixture.gateway.submit(record(opID: "op-3", payload: .attachSession(AttachSessionOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            sessionID: SessionID(rawValue: "session-1")
        ))), from: ClientID(rawValue: "client-1"))

        let response = try fixture.gateway.connect(clientID: ClientID(rawValue: "client-reconnect"), knownRoomSeq: 1)

        XCTAssertEqual(response.mode, .snapshotAndTail)
        XCTAssertEqual(response.baseSnapshot?.roomSeq, 2)
        XCTAssertEqual(response.tailRecords.map(\.roomSeq), [3])
        XCTAssertEqual(try response.reconstructReplica(existingSnapshot: nil), fixture.actor.snapshot)
    }

    func testRejectIsDeliveredToSubmittingClient() throws {
        let fixture = try makeFixture(snapshotInterval: 10)
        _ = try fixture.gateway.connect(clientID: ClientID(rawValue: "client-1"), knownRoomSeq: nil)
        _ = try fixture.gateway.connect(clientID: ClientID(rawValue: "client-2"), knownRoomSeq: nil)

        XCTAssertThrowsError(try fixture.gateway.submit(record(opID: "bad-op", payload: .moveSurface(MoveSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "missing"),
            xWorld: 10,
            yWorld: 20
        ))), from: ClientID(rawValue: "client-1"))) { error in
            XCTAssertEqual(
                error as? RoomGatewayReject,
                RoomGatewayReject(
                    roomID: RoomID(rawValue: "room-1"),
                    clientID: ClientID(rawValue: "client-1"),
                    opID: RoomOpID(rawValue: "bad-op"),
                    reason: RoomActorError.surfaceNotFound(TerminalSurfaceID(rawValue: "missing")).localizedDescription
                )
            )
        }

        XCTAssertEqual(
            fixture.gateway.deliveries(for: ClientID(rawValue: "client-1")),
            [.rejected(RoomGatewayReject(
                roomID: RoomID(rawValue: "room-1"),
                clientID: ClientID(rawValue: "client-1"),
                opID: RoomOpID(rawValue: "bad-op"),
                reason: RoomActorError.surfaceNotFound(TerminalSurfaceID(rawValue: "missing")).localizedDescription
            ))]
        )
        XCTAssertEqual(fixture.gateway.deliveries(for: ClientID(rawValue: "client-2")), [])
    }

    func testDuplicateSubmitOnlyNotifiesSubmittingClient() throws {
        let fixture = try makeFixture(snapshotInterval: 10)
        _ = try fixture.gateway.connect(clientID: ClientID(rawValue: "client-1"), knownRoomSeq: nil)
        _ = try fixture.gateway.connect(clientID: ClientID(rawValue: "client-2"), knownRoomSeq: nil)

        let op = record(opID: "dup-op", payload: .createSurface(CreateSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            xWorld: 0,
            yWorld: 0,
            cols: 80,
            rows: 24,
            profileID: "profile",
            terminalTemplate: nil
        )))
        _ = try fixture.gateway.submit(op, from: ClientID(rawValue: "client-1"))
        _ = try fixture.gateway.submit(op, from: ClientID(rawValue: "client-1"))

        XCTAssertEqual(
            fixture.gateway.deliveries(for: ClientID(rawValue: "client-1")),
            [
                .accepted(RoomOpRecord(
                    schemaVersion: .v1,
                    roomID: RoomID(rawValue: "room-1"),
                    roomSeq: 1,
                    opID: RoomOpID(rawValue: "dup-op"),
                    clientID: ClientID(rawValue: "client-1"),
                    submittedAtMillis: 100,
                    payload: op.payload
                )),
                .duplicate(RoomOpRecord(
                    schemaVersion: .v1,
                    roomID: RoomID(rawValue: "room-1"),
                    roomSeq: 1,
                    opID: RoomOpID(rawValue: "dup-op"),
                    clientID: ClientID(rawValue: "client-1"),
                    submittedAtMillis: 100,
                    payload: op.payload
                )),
            ]
        )
        XCTAssertEqual(
            fixture.gateway.deliveries(for: ClientID(rawValue: "client-2")),
            [
                .accepted(RoomOpRecord(
                    schemaVersion: .v1,
                    roomID: RoomID(rawValue: "room-1"),
                    roomSeq: 1,
                    opID: RoomOpID(rawValue: "dup-op"),
                    clientID: ClientID(rawValue: "client-1"),
                    submittedAtMillis: 100,
                    payload: op.payload
                ))
            ]
        )
    }

    func testPresenceAndSessionTrafficStayOutOfDurableCatchUp() throws {
        let fixture = try makeFixture(snapshotInterval: 10)
        _ = try applyStandardOps(with: fixture.gateway)
        _ = try fixture.gateway.connect(clientID: ClientID(rawValue: "client-live"), knownRoomSeq: nil)

        fixture.gateway.publishPresence("cursor moved")
        fixture.gateway.publishSession("session heartbeat")

        let response = try fixture.gateway.connect(clientID: ClientID(rawValue: "client-late"), knownRoomSeq: 1)

        XCTAssertEqual(
            fixture.gateway.ephemeralDeliveries(for: ClientID(rawValue: "client-live")),
            [.presence("cursor moved"), .session("session heartbeat")]
        )
        XCTAssertEqual(fixture.gateway.ephemeralDeliveries(for: ClientID(rawValue: "client-late")), [])
        XCTAssertEqual(response.tailRecords.map(\.payload), [
            .moveSurface(MoveSurfaceOp(surfaceID: TerminalSurfaceID(rawValue: "surface-1"), xWorld: 24, yWorld: 40)),
            .attachSession(AttachSessionOp(surfaceID: TerminalSurfaceID(rawValue: "surface-1"), sessionID: SessionID(rawValue: "session-1")))
        ])
    }

    private func makeFixture(snapshotInterval: UInt64) throws -> (actor: RoomActor, gateway: RoomGateway) {
        let journal = InMemoryRoomJournalStore()
        let snapshots = InMemoryRoomSnapshotStore()
        let actor = RoomActor(
            snapshot: emptySnapshot(),
            journalStore: journal,
            snapshotStore: snapshots,
            snapshotInterval: snapshotInterval
        )
        let gateway = RoomGateway(actor: actor, journalStore: journal, snapshotStore: snapshots)
        return (actor, gateway)
    }

    private func applyStandardOps(with gateway: RoomGateway) throws -> [RoomOpRecord] {
        let clientID = ClientID(rawValue: "client-1")
        return [
            try gateway.submit(record(opID: "op-1", payload: .createSurface(CreateSurfaceOp(
                surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
                xWorld: 0,
                yWorld: 0,
                cols: 80,
                rows: 24,
                profileID: "profile",
                terminalTemplate: nil
            ))), from: clientID).record,
            try gateway.submit(record(opID: "op-2", payload: .moveSurface(MoveSurfaceOp(
                surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
                xWorld: 24,
                yWorld: 40
            ))), from: clientID).record,
            try gateway.submit(record(opID: "op-3", payload: .attachSession(AttachSessionOp(
                surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
                sessionID: SessionID(rawValue: "session-1")
            ))), from: clientID).record,
        ]
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
