import XCTest
@testable import DemoApp

final class RoomReplicaTests: XCTestCase {
    func testOptimisticMoveAcceptanceConverges() throws {
        let replica = RoomReplica(clientID: ClientID(rawValue: "client-1"), snapshot: initialSnapshot())

        let pending = try replica.submit(.moveSurface(MoveSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            xWorld: 40,
            yWorld: 60
        )))

        XCTAssertEqual(replica.authoritativeSnapshot.surfaces.first?.xWorld, 0)
        XCTAssertEqual(replica.predictedSnapshot.surfaces.first?.xWorld, 40)
        XCTAssertEqual(replica.pendingOps.map(\.record.opID), [pending.opID])

        try replica.receiveAccepted(RoomOpRecord(
            schemaVersion: .v1,
            roomID: initialSnapshot().roomID,
            roomSeq: 1,
            opID: pending.opID,
            clientID: pending.clientID,
            submittedAtMillis: pending.submittedAtMillis,
            payload: pending.payload
        ))

        XCTAssertEqual(replica.pendingOps, [])
        XCTAssertEqual(replica.authoritativeSnapshot, replica.predictedSnapshot)
        XCTAssertEqual(replica.authoritativeSnapshot.surfaces.first?.xWorld, 40)
    }

    func testOptimisticResizeRejectRollsBackPrediction() throws {
        let replica = RoomReplica(clientID: ClientID(rawValue: "client-1"), snapshot: initialSnapshot())
        let pending = try replica.submit(.resizeSurface(ResizeSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            cols: 120,
            rows: 40
        )))

        XCTAssertEqual(replica.predictedSnapshot.surfaces.first?.cols, 120)

        try replica.receiveRejected(RoomGatewayReject(
            roomID: initialSnapshot().roomID,
            clientID: ClientID(rawValue: "client-1"),
            opID: pending.opID,
            reason: "resize_rejected"
        ))

        XCTAssertEqual(replica.pendingOps, [])
        XCTAssertEqual(replica.predictedSnapshot, replica.authoritativeSnapshot)
        XCTAssertEqual(replica.predictedSnapshot.surfaces.first?.cols, 80)
    }

    func testOptimisticReorderRejectRollsBackPrediction() throws {
        let replica = RoomReplica(clientID: ClientID(rawValue: "client-1"), snapshot: snapshotWithTwoSurfaces())
        let pending = try replica.submit(.setStackRank(SetStackRankOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-2"),
            targetRank: 0
        )))

        XCTAssertEqual(replica.predictedSnapshot.surfaces.map(\.id.rawValue), ["surface-2", "surface-1"])

        try replica.receiveRejected(RoomGatewayReject(
            roomID: snapshotWithTwoSurfaces().roomID,
            clientID: ClientID(rawValue: "client-1"),
            opID: pending.opID,
            reason: "rank_rejected"
        ))

        XCTAssertEqual(replica.predictedSnapshot.surfaces.map(\.id.rawValue), ["surface-1", "surface-2"])
    }

    func testPendingOpsRebaseOverAuthoritativeAccepts() throws {
        let replica = RoomReplica(clientID: ClientID(rawValue: "client-1"), snapshot: initialSnapshot())
        _ = try replica.submit(.createSurface(CreateSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-2"),
            xWorld: 20,
            yWorld: 30,
            cols: 100,
            rows: 30,
            profileID: "profile",
            terminalTemplate: nil
        )))
        _ = try replica.submit(.setStackRank(SetStackRankOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-2"),
            targetRank: 0
        )))

        try replica.receiveAccepted(RoomOpRecord(
            schemaVersion: .v1,
            roomID: initialSnapshot().roomID,
            roomSeq: 1,
            opID: RoomOpID(rawValue: "server-move"),
            clientID: ClientID(rawValue: "client-2"),
            submittedAtMillis: 50,
            payload: .moveSurface(MoveSurfaceOp(
                surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
                xWorld: 75,
                yWorld: 80
            ))
        ))

        XCTAssertEqual(replica.authoritativeSnapshot.surfaces.map(\.id.rawValue), ["surface-1"])
        XCTAssertEqual(replica.authoritativeSnapshot.surfaces.first?.xWorld, 75)
        XCTAssertEqual(replica.predictedSnapshot.surfaces.map(\.id.rawValue), ["surface-2", "surface-1"])
        XCTAssertEqual(replica.predictedSnapshot.surfaces.last?.xWorld, 75)
        XCTAssertEqual(replica.pendingOps.count, 2)
    }

    func testDuplicateAndOutOfOrderAuthoritativeEventsDoNotCorruptReplica() throws {
        let replica = RoomReplica(clientID: ClientID(rawValue: "client-1"), snapshot: initialSnapshot())
        let seqTwo = RoomOpRecord(
            schemaVersion: .v1,
            roomID: initialSnapshot().roomID,
            roomSeq: 2,
            opID: RoomOpID(rawValue: "server-2"),
            clientID: ClientID(rawValue: "client-2"),
            submittedAtMillis: 60,
            payload: .resizeSurface(ResizeSurfaceOp(
                surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
                cols: 120,
                rows: 40
            ))
        )
        let seqOne = RoomOpRecord(
            schemaVersion: .v1,
            roomID: initialSnapshot().roomID,
            roomSeq: 1,
            opID: RoomOpID(rawValue: "server-1"),
            clientID: ClientID(rawValue: "client-2"),
            submittedAtMillis: 50,
            payload: .moveSurface(MoveSurfaceOp(
                surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
                xWorld: 10,
                yWorld: 12
            ))
        )

        try replica.receiveAccepted(seqTwo)
        XCTAssertEqual(replica.authoritativeSnapshot.roomSeq, 0)

        try replica.receiveAccepted(seqOne)
        XCTAssertEqual(replica.authoritativeSnapshot.roomSeq, 2)
        XCTAssertEqual(replica.authoritativeSnapshot.surfaces.first?.xWorld, 10)
        XCTAssertEqual(replica.authoritativeSnapshot.surfaces.first?.cols, 120)

        try replica.receiveAccepted(seqOne)
        XCTAssertEqual(replica.authoritativeSnapshot.roomSeq, 2)
    }

    func testTimelineRecordsAcceptRejectAndRebase() throws {
        let replica = RoomReplica(clientID: ClientID(rawValue: "client-1"), snapshot: initialSnapshot())
        let pending = try replica.submit(.moveSurface(MoveSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            xWorld: 10,
            yWorld: 12
        )))
        try replica.receiveRejected(RoomGatewayReject(
            roomID: initialSnapshot().roomID,
            clientID: ClientID(rawValue: "client-1"),
            opID: pending.opID,
            reason: "rejected_by_server"
        ))

        XCTAssertTrue(replica.timeline.contains(where: { $0.contains("submit") }))
        XCTAssertTrue(replica.timeline.contains(where: { $0.contains("reject") }))
        XCTAssertTrue(replica.timeline.contains(where: { $0.contains("rebase") }))
    }

    private func initialSnapshot() -> DurableRoomSnapshot {
        DurableRoomSnapshot(
            schemaVersion: .v1,
            roomID: RoomID(rawValue: "room-1"),
            roomSeq: 0,
            renderProfileIDs: ["profile"],
            surfaces: [
                DurableRoomSurface(
                    id: TerminalSurfaceID(rawValue: "surface-1"),
                    sessionID: nil,
                    xWorld: 0,
                    yWorld: 0,
                    cols: 80,
                    rows: 24,
                    stackRank: 0,
                    profileID: "profile",
                    title: nil,
                    state: .provisioning,
                    createdBy: UserID(rawValue: "user-1"),
                    createdAtMillis: 1
                )
            ],
            controlLeases: []
        )
    }

    private func snapshotWithTwoSurfaces() -> DurableRoomSnapshot {
        DurableRoomSnapshot(
            schemaVersion: .v1,
            roomID: RoomID(rawValue: "room-1"),
            roomSeq: 0,
            renderProfileIDs: ["profile"],
            surfaces: [
                DurableRoomSurface(
                    id: TerminalSurfaceID(rawValue: "surface-1"),
                    sessionID: nil,
                    xWorld: 0,
                    yWorld: 0,
                    cols: 80,
                    rows: 24,
                    stackRank: 0,
                    profileID: "profile",
                    title: nil,
                    state: .provisioning,
                    createdBy: UserID(rawValue: "user-1"),
                    createdAtMillis: 1
                ),
                DurableRoomSurface(
                    id: TerminalSurfaceID(rawValue: "surface-2"),
                    sessionID: nil,
                    xWorld: 20,
                    yWorld: 30,
                    cols: 80,
                    rows: 24,
                    stackRank: 1,
                    profileID: "profile",
                    title: nil,
                    state: .provisioning,
                    createdBy: UserID(rawValue: "user-2"),
                    createdAtMillis: 2
                ),
            ],
            controlLeases: []
        )
    }
}
