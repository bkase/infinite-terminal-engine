import XCTest
@testable import DemoApp

@MainActor
final class SurfaceLifecycleCoordinatorTests: XCTestCase {
    func testCreateSurfaceToAttachedSessionLifecycle() throws {
        let fixture = try makeFixture()

        let state = try fixture.coordinator.createSurface(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            sessionID: SessionID(rawValue: "session-1"),
            clientID: ClientID(rawValue: "client-1"),
            cols: 80,
            rows: 24,
            profileID: "profile"
        )

        XCTAssertEqual(state.phase, .attached)
        XCTAssertEqual(state.roomState, .attached)
        XCTAssertEqual(state.sessionStatus, .running)
    }

    func testCloseSurfaceTearsDownLifecycle() throws {
        let fixture = try makeFixture()
        _ = try fixture.coordinator.createSurface(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            sessionID: SessionID(rawValue: "session-1"),
            clientID: ClientID(rawValue: "client-1"),
            cols: 80,
            rows: 24,
            profileID: "profile"
        )

        let closed = try fixture.coordinator.closeSurface(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            clientID: ClientID(rawValue: "client-1")
        )

        XCTAssertEqual(closed?.phase, .closing)
        XCTAssertNil(fixture.coordinator.state(for: TerminalSurfaceID(rawValue: "surface-1")))
        XCTAssertTrue(fixture.sessionDirectory.activeSessionIDs().isEmpty)
    }

    func testRoomUpSessionDownAndClientFailureBecomeDegradedAndErrorSeparately() throws {
        let fixture = try makeFixture()
        _ = try fixture.coordinator.createSurface(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            sessionID: SessionID(rawValue: "session-1"),
            clientID: ClientID(rawValue: "client-1"),
            cols: 80,
            rows: 24,
            profileID: "profile"
        )
        let client = fixture.makeClient()
        fixture.coordinator.subscribeSurface(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            client: client,
            clientID: ClientID(rawValue: "viewer-1"),
            leaseEpoch: 1,
            token: try fixture.token(sessionID: "session-1", clientID: "viewer-1")
        )

        fixture.backends.value[SessionID(rawValue: "session-1")]?.emitFailure("session backend failed")
        fixture.coordinator.pollClients(surfaceID: TerminalSurfaceID(rawValue: "surface-1"))

        XCTAssertEqual(
            fixture.coordinator.state(for: TerminalSurfaceID(rawValue: "surface-1"))?.phase,
            .error
        )

        let client2 = fixture.makeClient()
        _ = try fixture.coordinator.createSurface(
            surfaceID: TerminalSurfaceID(rawValue: "surface-2"),
            sessionID: SessionID(rawValue: "session-2"),
            clientID: ClientID(rawValue: "client-1"),
            cols: 80,
            rows: 24,
            profileID: "profile"
        )
        fixture.coordinator.subscribeSurface(
            surfaceID: TerminalSurfaceID(rawValue: "surface-2"),
            client: client2,
            clientID: ClientID(rawValue: "viewer-2"),
            leaseEpoch: 1,
            token: try fixture.token(sessionID: "session-2", clientID: "viewer-2")
        )
        fixture.currentLeaseEpoch.value = 2
        fixture.server.noteLeaseEpochChanged(for: SessionID(rawValue: "session-2"))
        fixture.coordinator.pollClients(surfaceID: TerminalSurfaceID(rawValue: "surface-2"))

        XCTAssertEqual(
            fixture.coordinator.state(for: TerminalSurfaceID(rawValue: "surface-2"))?.phase,
            .degraded
        )
    }

    func testMultiViewSharedSurfaceKeepsAttachedLifecycleForBothViewers() throws {
        let fixture = try makeFixture()
        _ = try fixture.coordinator.createSurface(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            sessionID: SessionID(rawValue: "session-1"),
            clientID: ClientID(rawValue: "client-1"),
            cols: 80,
            rows: 24,
            profileID: "profile"
        )

        let viewer1 = fixture.makeClient()
        let viewer2 = fixture.makeClient()
        let token1 = try fixture.token(sessionID: "session-1", clientID: "viewer-1")
        let token2 = try fixture.token(sessionID: "session-1", clientID: "viewer-2")

        fixture.coordinator.subscribeSurface(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            client: viewer1,
            clientID: ClientID(rawValue: "viewer-1"),
            leaseEpoch: 1,
            token: token1
        )
        fixture.coordinator.subscribeSurface(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            client: viewer2,
            clientID: ClientID(rawValue: "viewer-2"),
            leaseEpoch: 1,
            token: token2
        )

        XCTAssertEqual(
            fixture.coordinator.state(for: TerminalSurfaceID(rawValue: "surface-1"))?.phase,
            .attached
        )
        XCTAssertEqual(viewer1.state(for: TerminalSurfaceID(rawValue: "surface-1"))?.phase, .live)
        XCTAssertEqual(viewer2.state(for: TerminalSurfaceID(rawValue: "surface-1"))?.phase, .live)
    }

    private func makeFixture() throws -> SurfaceLifecycleFixture {
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
        let sessionDirectory = SessionDirectory()
        let backendStore = MutableBox<[SessionID: ReplayLogPTYBackend]>([:])
        let currentLeaseEpoch = MutableBox<UInt64>(1)
        let authenticator = SessionTransportAuthenticator(secret: Data("transport-secret".utf8))
        let server = SessionTransportServer(
            directory: sessionDirectory,
            authenticator: authenticator,
            leaseEpochProvider: { _ in currentLeaseEpoch.value },
            nowMillis: { 100 }
        )
        let resizeCoordinator = SessionResizeCoordinator(directory: sessionDirectory)
        let coordinator = SurfaceLifecycleCoordinator(
            actor: actor,
            gateway: gateway,
            sessionDirectory: sessionDirectory,
            resizeCoordinator: resizeCoordinator,
            backendFactory: { sessionID in
                let backend = ReplayLogPTYBackend()
                backendStore.value[sessionID] = backend
                backend.emitOutput(Array("screen".utf8))
                return backend
            }
        )
        return SurfaceLifecycleFixture(
            coordinator: coordinator,
            sessionDirectory: sessionDirectory,
            server: server,
            authenticator: authenticator,
            backends: backendStore,
            currentLeaseEpoch: currentLeaseEpoch
        )
    }
}

@MainActor
private final class SurfaceLifecycleFixture {
    let coordinator: SurfaceLifecycleCoordinator
    let sessionDirectory: SessionDirectory
    let server: SessionTransportServer
    let authenticator: SessionTransportAuthenticator
    let backends: MutableBox<[SessionID: ReplayLogPTYBackend]>
    let currentLeaseEpoch: MutableBox<UInt64>

    init(
        coordinator: SurfaceLifecycleCoordinator,
        sessionDirectory: SessionDirectory,
        server: SessionTransportServer,
        authenticator: SessionTransportAuthenticator,
        backends: MutableBox<[SessionID: ReplayLogPTYBackend]>,
        currentLeaseEpoch: MutableBox<UInt64>
    ) {
        self.coordinator = coordinator
        self.sessionDirectory = sessionDirectory
        self.server = server
        self.authenticator = authenticator
        self.backends = backends
        self.currentLeaseEpoch = currentLeaseEpoch
    }

    func makeClient() -> SessionClient {
        SessionClient(
            connectHandler: { [server] request in
                try server.connect(request)
            },
            adapterFactory: { _, _ in
                TestSurfaceLifecycleAdapter()
            }
        )
    }

    func token(sessionID: String, clientID: String) throws -> String {
        try authenticator.issueToken(for: SessionTransportTokenClaims(
            sessionID: SessionID(rawValue: sessionID),
            clientID: ClientID(rawValue: clientID),
            leaseEpoch: 1,
            issuedAtMillis: 90,
            expiresAtMillis: 130
        ))
    }
}

@MainActor
private final class TestSurfaceLifecycleAdapter: SessionSurfaceAdapter {
    func ingestOutput(_ text: String) {
        _ = text
    }

    func shutdown() {}
}

private final class MutableBox<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
