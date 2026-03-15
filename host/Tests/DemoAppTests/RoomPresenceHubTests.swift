import XCTest
@testable import DemoApp

final class RoomPresenceHubTests: XCTestCase {
    func testPresenceUpdateFansOutWithoutTouchingDurableState() throws {
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
            snapshotStore: snapshots,
            snapshotInterval: 10
        )
        let presence = RoomPresenceHub(roomID: RoomID(rawValue: "room-1"), ttlMillis: 10)
        _ = presence.connect(clientID: ClientID(rawValue: "client-1"), nowMillis: 1)
        _ = presence.connect(clientID: ClientID(rawValue: "client-2"), nowMillis: 1)

        let beforeSnapshot = actor.snapshot
        let beforeRecords = try journal.records(for: RoomID(rawValue: "room-1"), after: 0)

        let payload = RoomPresencePayload(
            cameraOriginX: 10,
            cameraOriginY: 20,
            zoom: 1.5,
            viewportWidth: 1280,
            viewportHeight: 720,
            cursorWorldX: 30,
            cursorWorldY: 40,
            selectedSurfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            controlSessionID: SessionID(rawValue: "session-1")
        )
        let updated = presence.update(
            clientID: ClientID(rawValue: "client-1"),
            userID: UserID(rawValue: "user-1"),
            payload: payload,
            nowMillis: 2
        )

        XCTAssertEqual(
            presence.deliveries(for: ClientID(rawValue: "client-2")),
            [.snapshot([]), .updated(updated)]
        )
        XCTAssertEqual(actor.snapshot, beforeSnapshot)
        XCTAssertEqual(try journal.records(for: RoomID(rawValue: "room-1"), after: 0), beforeRecords)
    }

    func testPresenceReconnectReturnsActiveSnapshot() {
        let presence = RoomPresenceHub(roomID: RoomID(rawValue: "room-1"), ttlMillis: 10)
        let payload = RoomPresencePayload(
            cameraOriginX: 0,
            cameraOriginY: 0,
            zoom: 1,
            viewportWidth: 800,
            viewportHeight: 600,
            cursorWorldX: nil,
            cursorWorldY: nil,
            selectedSurfaceID: nil,
            controlSessionID: nil
        )
        _ = presence.connect(clientID: ClientID(rawValue: "client-1"), nowMillis: 1)
        let state = presence.update(
            clientID: ClientID(rawValue: "client-1"),
            userID: UserID(rawValue: "user-1"),
            payload: payload,
            nowMillis: 2
        )
        presence.disconnect(clientID: ClientID(rawValue: "client-2"))

        let reconnectSnapshot = presence.connect(clientID: ClientID(rawValue: "client-2"), nowMillis: 5)

        XCTAssertEqual(reconnectSnapshot, [state])
        XCTAssertEqual(
            presence.deliveries(for: ClientID(rawValue: "client-2")),
            [.snapshot([state])]
        )
    }

    func testPresenceExpiryRemovesStaleEntriesAndBroadcastsExpiry() {
        let presence = RoomPresenceHub(roomID: RoomID(rawValue: "room-1"), ttlMillis: 5)
        _ = presence.connect(clientID: ClientID(rawValue: "client-1"), nowMillis: 1)
        _ = presence.connect(clientID: ClientID(rawValue: "client-2"), nowMillis: 1)
        _ = presence.update(
            clientID: ClientID(rawValue: "client-1"),
            userID: UserID(rawValue: "user-1"),
            payload: RoomPresencePayload(
                cameraOriginX: 1,
                cameraOriginY: 2,
                zoom: 1,
                viewportWidth: 640,
                viewportHeight: 480,
                cursorWorldX: 3,
                cursorWorldY: 4,
                selectedSurfaceID: nil,
                controlSessionID: nil
            ),
            nowMillis: 2
        )

        let expired = presence.expire(nowMillis: 7)

        XCTAssertEqual(expired, [ClientID(rawValue: "client-1")])
        XCTAssertEqual(presence.activePresence(nowMillis: 7), [])
        XCTAssertTrue(
            presence.deliveries(for: ClientID(rawValue: "client-2")).contains(.expired(ClientID(rawValue: "client-1")))
        )
    }
}
