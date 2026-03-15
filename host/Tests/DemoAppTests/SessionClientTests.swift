import XCTest
@testable import DemoApp

@MainActor
final class SessionClientTests: XCTestCase {
    func testSubscribeBootstrapsThenPollsLiveOutput() throws {
        let fixture = try makeFixture()
        let client = fixture.makeClient()

        client.subscribe(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            sessionID: SessionID(rawValue: "session-1"),
            clientID: ClientID(rawValue: "client-1"),
            leaseEpoch: 1,
            token: try fixture.token(sessionID: "session-1", clientID: "client-1", leaseEpoch: 1)
        )

        XCTAssertEqual(
            client.state(for: TerminalSurfaceID(rawValue: "surface-1")),
            SessionSurfaceState(
                surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
                sessionID: SessionID(rawValue: "session-1"),
                adapterGeneration: 1,
                lastOutputSeq: 6,
                phase: .live
            )
        )
        XCTAssertEqual(fixture.adapters[0].text, "screen")

        fixture.backends[0].emitOutput(Array("abc".utf8))
        client.poll(surfaceID: TerminalSurfaceID(rawValue: "surface-1"))

        XCTAssertEqual(fixture.adapters[0].text, "screenabc")
        XCTAssertEqual(client.state(for: TerminalSurfaceID(rawValue: "surface-1"))?.lastOutputSeq, 9)
    }

    func testReconnectCreatesFreshAdapterAndReplaysBootstrap() throws {
        let fixture = try makeFixture()
        let client = fixture.makeClient()
        let surfaceID = TerminalSurfaceID(rawValue: "surface-1")

        client.subscribe(
            surfaceID: surfaceID,
            sessionID: SessionID(rawValue: "session-1"),
            clientID: ClientID(rawValue: "client-1"),
            leaseEpoch: 1,
            token: try fixture.token(sessionID: "session-1", clientID: "client-1", leaseEpoch: 1)
        )
        fixture.backends[0].emitOutput(Array("abc".utf8))
        client.poll(surfaceID: surfaceID)

        let firstAdapter = fixture.adapters[0]
        client.reconnect(surfaceID: surfaceID)

        XCTAssertEqual(firstAdapter.shutdownCount, 1)
        XCTAssertEqual(fixture.adapters.count, 2)
        XCTAssertEqual(fixture.adapters[1].text, "screenabc")
        XCTAssertEqual(client.state(for: surfaceID)?.adapterGeneration, 2)
    }

    func testFailedSurfaceStateDoesNotTearDownHealthySurface() throws {
        let fixture = try makeFixture()
        let client = fixture.makeClient()
        let surface1 = TerminalSurfaceID(rawValue: "surface-1")
        let surface2 = TerminalSurfaceID(rawValue: "surface-2")

        client.subscribe(
            surfaceID: surface1,
            sessionID: SessionID(rawValue: "session-1"),
            clientID: ClientID(rawValue: "client-1"),
            leaseEpoch: 1,
            token: try fixture.token(sessionID: "session-1", clientID: "client-1", leaseEpoch: 1)
        )
        client.subscribe(
            surfaceID: surface2,
            sessionID: SessionID(rawValue: "session-2"),
            clientID: ClientID(rawValue: "client-2"),
            leaseEpoch: 1,
            token: try fixture.token(sessionID: "session-2", clientID: "client-2", leaseEpoch: 1)
        )

        fixture.backends[0].emitFailure("session backend failed")
        fixture.backends[1].emitOutput(Array("ok".utf8))
        client.poll(surfaceID: surface1)
        client.poll(surfaceID: surface2)

        XCTAssertEqual(
            client.state(for: surface1)?.phase,
            .failed("session backend failed")
        )
        XCTAssertEqual(
            client.state(for: surface2)?.phase,
            .live
        )
        XCTAssertEqual(
            client.state(for: surface1)?.phase.overlayText,
            "Failed: session backend failed"
        )
        XCTAssertEqual(fixture.adapters[1].text, "screenok")
    }

    func testUnsubscribeTearsDownAdapterAndRemovesSurfaceState() throws {
        let fixture = try makeFixture()
        let client = fixture.makeClient()
        let surfaceID = TerminalSurfaceID(rawValue: "surface-1")

        client.subscribe(
            surfaceID: surfaceID,
            sessionID: SessionID(rawValue: "session-1"),
            clientID: ClientID(rawValue: "client-1"),
            leaseEpoch: 1,
            token: try fixture.token(sessionID: "session-1", clientID: "client-1", leaseEpoch: 1)
        )
        let adapter = fixture.adapters[0]

        client.unsubscribe(surfaceID: surfaceID)

        XCTAssertNil(client.state(for: surfaceID))
        XCTAssertEqual(adapter.shutdownCount, 1)
    }

    private func makeFixture() throws -> SessionClientFixture {
        let directory = SessionDirectory()
        let backends = [ReplayLogPTYBackend(), ReplayLogPTYBackend()]
        let sessionIDs = [SessionID(rawValue: "session-1"), SessionID(rawValue: "session-2")]

        for (index, sessionID) in sessionIDs.enumerated() {
            let actor = try directory.provision(
                sessionID: sessionID,
                roomID: RoomID(rawValue: "room-1"),
                surfaceID: TerminalSurfaceID(rawValue: "surface-\(index + 1)"),
                initialSize: TerminalSessionSize(cols: 80, rows: 24)
            ) {
                backends[index]
            }
            try actor.start()
            backends[index].emitOutput(Array("screen".utf8))
        }

        let authenticator = SessionTransportAuthenticator(secret: Data("transport-secret".utf8))
        let server = SessionTransportServer(
            directory: directory,
            authenticator: authenticator,
            leaseEpochProvider: { _ in 1 },
            nowMillis: { 100 }
        )
        return SessionClientFixture(
            server: server,
            authenticator: authenticator,
            backends: backends
        )
    }
}

@MainActor
private final class SessionClientFixture {
    let server: SessionTransportServer
    let authenticator: SessionTransportAuthenticator
    let backends: [ReplayLogPTYBackend]
    private(set) var adapters: [TestSessionSurfaceAdapter] = []

    init(
        server: SessionTransportServer,
        authenticator: SessionTransportAuthenticator,
        backends: [ReplayLogPTYBackend]
    ) {
        self.server = server
        self.authenticator = authenticator
        self.backends = backends
    }

    func makeClient() -> SessionClient {
        SessionClient(
            connectHandler: { [server] request in
                try server.connect(request)
            },
            adapterFactory: { [weak self] _, _ in
                let adapter = TestSessionSurfaceAdapter()
                self?.adapters.append(adapter)
                return adapter
            }
        )
    }

    func token(sessionID: String, clientID: String, leaseEpoch: UInt64) throws -> String {
        try authenticator.issueToken(for: SessionTransportTokenClaims(
            sessionID: SessionID(rawValue: sessionID),
            clientID: ClientID(rawValue: clientID),
            leaseEpoch: leaseEpoch,
            issuedAtMillis: 90,
            expiresAtMillis: 130
        ))
    }
}

@MainActor
private final class TestSessionSurfaceAdapter: SessionSurfaceAdapter {
    private(set) var text = ""
    private(set) var shutdownCount = 0

    func ingestOutput(_ text: String) {
        self.text.append(text)
    }

    func shutdown() {
        shutdownCount += 1
    }
}
