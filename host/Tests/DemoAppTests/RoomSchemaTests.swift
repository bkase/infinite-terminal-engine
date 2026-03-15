import XCTest
@testable import DemoApp

final class RoomSchemaTests: XCTestCase {
    func testRoomOpRoundTripsAllDurableVocabularyCases() throws {
        let records: [RoomOpRecord] = [
            makeRecord(.createSurface(CreateSurfaceOp(
                surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
                xWorld: 10,
                yWorld: 20,
                cols: 80,
                rows: 24,
                profileID: "collab-pragmata-v1",
                terminalTemplate: "shell"
            ))),
            makeRecord(.moveSurface(MoveSurfaceOp(surfaceID: TerminalSurfaceID(rawValue: "surface-1"), xWorld: 40, yWorld: 60))),
            makeRecord(.resizeSurface(ResizeSurfaceOp(surfaceID: TerminalSurfaceID(rawValue: "surface-1"), cols: 120, rows: 40))),
            makeRecord(.setStackRank(SetStackRankOp(surfaceID: TerminalSurfaceID(rawValue: "surface-1"), targetRank: 2))),
            makeRecord(.closeSurface(CloseSurfaceOp(surfaceID: TerminalSurfaceID(rawValue: "surface-1")))),
            makeRecord(.setSurfaceTitle(SetSurfaceTitleOp(surfaceID: TerminalSurfaceID(rawValue: "surface-1"), title: "Build"))),
            makeRecord(.attachSession(AttachSessionOp(surfaceID: TerminalSurfaceID(rawValue: "surface-1"), sessionID: SessionID(rawValue: "session-1")))),
            makeRecord(.detachSession(DetachSessionOp(surfaceID: TerminalSurfaceID(rawValue: "surface-1")))),
            makeRecord(.acquireControl(AcquireControlOp(sessionID: SessionID(rawValue: "session-1"), holderUserID: UserID(rawValue: "user-1")))),
            makeRecord(.releaseControl(ReleaseControlOp(sessionID: SessionID(rawValue: "session-1")))),
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for record in records {
            let data = try encoder.encode(record)
            XCTAssertEqual(try decoder.decode(RoomOpRecord.self, from: data), record)
            try record.validate()
        }
    }

    func testOpValidationRejectsIllegalPayloads() {
        let invalidCreate = makeRecord(.createSurface(CreateSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            xWorld: 0,
            yWorld: 0,
            cols: 0,
            rows: 24,
            profileID: "profile",
            terminalTemplate: nil
        )))
        let invalidRank = makeRecord(.setStackRank(SetStackRankOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            targetRank: -1
        )))
        let invalidAcquire = makeRecord(.acquireControl(AcquireControlOp(
            sessionID: SessionID(rawValue: ""),
            holderUserID: UserID(rawValue: "user-1")
        )))

        XCTAssertThrowsError(try invalidCreate.validate()) { error in
            XCTAssertEqual(error as? RoomSchemaValidationError, .nonPositiveDimension("cols"))
        }
        XCTAssertThrowsError(try invalidRank.validate()) { error in
            XCTAssertEqual(error as? RoomSchemaValidationError, .negativeStackRank)
        }
        XCTAssertThrowsError(try invalidAcquire.validate()) { error in
            XCTAssertEqual(error as? RoomSchemaValidationError, .emptyField("session_id"))
        }
    }

    func testSnapshotCompatibilityForEmptyAndPopulatedRooms() throws {
        let empty = DurableRoomSnapshot(
            schemaVersion: .v1,
            roomID: RoomID(rawValue: "room-empty"),
            roomSeq: 0,
            renderProfileIDs: ["collab-pragmata-v1"],
            surfaces: [],
            controlLeases: []
        )
        let populated = DurableRoomSnapshot(
            schemaVersion: .v1,
            roomID: RoomID(rawValue: "room-1"),
            roomSeq: 12,
            renderProfileIDs: ["collab-pragmata-v1"],
            surfaces: [
                DurableRoomSurface(
                    id: TerminalSurfaceID(rawValue: "surface-1"),
                    sessionID: SessionID(rawValue: "session-1"),
                    xWorld: 24,
                    yWorld: 40,
                    cols: 80,
                    rows: 24,
                    stackRank: 0,
                    profileID: "collab-pragmata-v1",
                    title: "shell",
                    state: .attached,
                    createdBy: UserID(rawValue: "user-1"),
                    createdAtMillis: 1_234
                )
            ],
            controlLeases: [
                ControlLeaseRecord(
                    sessionID: SessionID(rawValue: "session-1"),
                    holderUserID: UserID(rawValue: "user-1"),
                    leaseEpoch: 3,
                    acquiredAtMillis: 1_200,
                    expiresAtMillis: 1_240
                )
            ]
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for snapshot in [empty, populated] {
            let data = try encoder.encode(snapshot)
            XCTAssertEqual(try decoder.decode(DurableRoomSnapshot.self, from: data), snapshot)
            try snapshot.validate()
        }
    }

    func testSnapshotValidationRejectsDuplicateRanksAndMissingAttachedSession() {
        let duplicateRanks = DurableRoomSnapshot(
            schemaVersion: .v1,
            roomID: RoomID(rawValue: "room-1"),
            roomSeq: 2,
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
                    yWorld: 20,
                    cols: 80,
                    rows: 24,
                    stackRank: 0,
                    profileID: "profile",
                    title: nil,
                    state: .provisioning,
                    createdBy: UserID(rawValue: "user-2"),
                    createdAtMillis: 2
                ),
            ],
            controlLeases: []
        )
        let missingSession = DurableRoomSurface(
            id: TerminalSurfaceID(rawValue: "surface-3"),
            sessionID: nil,
            xWorld: 0,
            yWorld: 0,
            cols: 80,
            rows: 24,
            stackRank: 1,
            profileID: "profile",
            title: nil,
            state: .attached,
            createdBy: UserID(rawValue: "user-1"),
            createdAtMillis: 3
        )

        XCTAssertThrowsError(try duplicateRanks.validate()) { error in
            XCTAssertEqual(error as? RoomSchemaValidationError, .duplicateStackRank(0))
        }
        XCTAssertThrowsError(try missingSession.validate()) { error in
            XCTAssertEqual(
                error as? RoomSchemaValidationError,
                .missingSessionForAttachedSurface(TerminalSurfaceID(rawValue: "surface-3"))
            )
        }
    }

    func testPersistenceRecordsRoundTripAndValidate() throws {
        let leaseRecord = ControlLeaseRecord(
            sessionID: SessionID(rawValue: "session-1"),
            holderUserID: UserID(rawValue: "user-1"),
            leaseEpoch: 3,
            acquiredAtMillis: 100,
            expiresAtMillis: 140
        )
        let snapshot = DurableRoomSnapshot(
            schemaVersion: .v1,
            roomID: RoomID(rawValue: "room-1"),
            roomSeq: 10,
            renderProfileIDs: ["profile"],
            surfaces: [],
            controlLeases: [leaseRecord]
        )
        let snapshotRecord = RoomSnapshotRecord(
            roomID: RoomID(rawValue: "room-1"),
            roomSeq: 10,
            schemaVersion: .v1,
            checksum: "abc123",
            snapshot: snapshot,
            writtenAtMillis: 50
        )
        let sessionRecord = SessionAttachmentRecord(
            sessionID: SessionID(rawValue: "session-1"),
            roomID: RoomID(rawValue: "room-1"),
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            cols: 80,
            rows: 24,
            bootstrapPolicy: .redraw,
            status: .running,
            updatedAtMillis: 100
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        XCTAssertEqual(try decoder.decode(RoomSnapshotRecord.self, from: encoder.encode(snapshotRecord)), snapshotRecord)
        XCTAssertEqual(try decoder.decode(SessionAttachmentRecord.self, from: encoder.encode(sessionRecord)), sessionRecord)
        XCTAssertEqual(try decoder.decode(ControlLeaseRecord.self, from: encoder.encode(leaseRecord)), leaseRecord)

        try snapshotRecord.validate()
        try sessionRecord.validate()
        try leaseRecord.validate()
    }

    private func makeRecord(_ payload: RoomOperationPayload) -> RoomOpRecord {
        RoomOpRecord(
            schemaVersion: .v1,
            roomID: RoomID(rawValue: "room-1"),
            roomSeq: nil,
            opID: RoomOpID(rawValue: UUID().uuidString),
            clientID: ClientID(rawValue: "client-1"),
            submittedAtMillis: 1_000,
            payload: payload
        )
    }
}
