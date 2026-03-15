import XCTest
@testable import DemoApp

final class SessionTransportTests: XCTestCase {
    func testAuthSuccessBootstrapAndLiveMessagesStayOrdered() throws {
        let fixture = try makeFixture(currentLeaseEpoch: 7)
        let request = try fixture.connectRequest(clientID: "client-1", leaseEpoch: 7)

        let connection = try fixture.server.connect(request)
        XCTAssertEqual(
            connection.drainMessages(),
            [
                .bootstrap(SessionBootstrap(
                    bytes: Array("screen".utf8),
                    outputSeqStart: 1,
                    outputSeqEnd: 6,
                    size: TerminalSessionSize(cols: 80, rows: 24),
                    status: .running,
                    exitCode: nil,
                    failureReason: nil
                )),
                .status(SessionStatusRecord(
                    status: .running,
                    outputSeq: 6,
                    exitCode: nil,
                    failureReason: nil,
                    resize: acknowledgedResize(size: TerminalSessionSize(cols: 80, rows: 24))
                )),
            ]
        )

        fixture.backend.emitOutput(Array("abc".utf8))
        XCTAssertEqual(
            connection.drainMessages(),
            [
                .output(SessionOutputChunk(seqStart: 7, seqEnd: 9, bytes: Array("abc".utf8))),
            ]
        )
        XCTAssertEqual(connection.diagnostics().resumeMode, .bootstrap)
    }

    func testAuthRejectsBadTokenAndStaleLeaseEpoch() throws {
        let fixture = try makeFixture(currentLeaseEpoch: 9)
        var request = try fixture.connectRequest(clientID: "client-1", leaseEpoch: 9)
        request = SessionTransportConnectRequest(
            sessionID: request.sessionID,
            clientID: request.clientID,
            leaseEpoch: request.leaseEpoch,
            token: request.token + "tampered",
            reconnectAfterOutputSeq: request.reconnectAfterOutputSeq
        )

        XCTAssertThrowsError(try fixture.server.connect(request)) { error in
            XCTAssertEqual(error as? SessionTransportError, .invalidTokenSignature)
        }

        let staleEpochRequest = try fixture.connectRequest(clientID: "client-1", leaseEpoch: 8)
        XCTAssertThrowsError(try fixture.server.connect(staleEpochRequest)) { error in
            XCTAssertEqual(error as? SessionTransportError, .leaseEpochMismatch(expected: 9, actual: 8))
        }
    }

    func testReconnectFromKnownAnchorReplaysOnlyMissingOutput() throws {
        let fixture = try makeFixture(currentLeaseEpoch: 5)
        let initial = try fixture.server.connect(try fixture.connectRequest(clientID: "client-1", leaseEpoch: 5))
        XCTAssertEqual(initial.drainMessages().count, 2)

        fixture.backend.emitOutput(Array("abc".utf8))
        fixture.backend.emitOutput(Array("de".utf8))
        _ = initial.drainMessages()
        initial.disconnect(reason: "simulate drop")

        let reconnect = try fixture.server.connect(try fixture.connectRequest(
            clientID: "client-1",
            leaseEpoch: 5,
            reconnectAfterOutputSeq: 8
        ))

        XCTAssertEqual(
            reconnect.drainMessages(),
            [
                .output(SessionOutputChunk(seqStart: 9, seqEnd: 9, bytes: Array("c".utf8))),
                .output(SessionOutputChunk(seqStart: 10, seqEnd: 11, bytes: Array("de".utf8))),
                .status(SessionStatusRecord(
                    status: .running,
                    outputSeq: 11,
                    exitCode: nil,
                    failureReason: nil,
                    resize: acknowledgedResize(size: TerminalSessionSize(cols: 80, rows: 24))
                )),
            ]
        )
        XCTAssertEqual(reconnect.diagnostics().resumeMode, .replay)
    }

    func testStaleAnchorFallsBackToBootstrap() throws {
        let fixture = try makeFixture(currentLeaseEpoch: 5)
        let connection = try fixture.server.connect(try fixture.connectRequest(
            clientID: "client-1",
            leaseEpoch: 5,
            reconnectAfterOutputSeq: 99
        ))

        XCTAssertEqual(connection.diagnostics().resumeMode, .staleAnchorBootstrap)
        XCTAssertEqual(
            connection.drainMessages(),
            [
                .bootstrap(SessionBootstrap(
                    bytes: Array("screen".utf8),
                    outputSeqStart: 1,
                    outputSeqEnd: 6,
                    size: TerminalSessionSize(cols: 80, rows: 24),
                    status: .running,
                    exitCode: nil,
                    failureReason: nil
                )),
                .status(SessionStatusRecord(
                    status: .running,
                    outputSeq: 6,
                    exitCode: nil,
                    failureReason: nil,
                    resize: acknowledgedResize(size: TerminalSessionSize(cols: 80, rows: 24))
                )),
            ]
        )
    }

    func testLeaseRevokedMessageIsQueuedAndInputIsRejectedAfterEpochChange() throws {
        let fixture = try makeFixture(currentLeaseEpoch: 3)
        let connection = try fixture.server.connect(try fixture.connectRequest(clientID: "client-1", leaseEpoch: 3))
        _ = connection.drainMessages()

        fixture.currentLeaseEpoch = 4
        fixture.server.noteLeaseEpochChanged(for: SessionID(rawValue: "session-1"))

        XCTAssertEqual(
            connection.drainMessages(),
            [
                .leaseRevoked(SessionTransportLeaseRevoked(previousLeaseEpoch: 3, currentLeaseEpoch: 4)),
            ]
        )

        XCTAssertThrowsError(try connection.sendInput(SessionTransportInputFrame(
            clientInputSeq: 1,
            bytes: Array("ls\n".utf8)
        ))) { error in
            XCTAssertEqual(error as? SessionTransportError, .leaseRevoked(currentLeaseEpoch: 4))
        }
    }

    func testExpiredTokenIsRejected() throws {
        let directory = SessionDirectory()
        let backend = ReplayLogPTYBackend()
        let actor = try directory.provision(
            sessionID: SessionID(rawValue: "session-1"),
            roomID: RoomID(rawValue: "room-1"),
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            initialSize: TerminalSessionSize(cols: 80, rows: 24)
        ) {
            backend
        }
        try actor.start()

        let authenticator = SessionTransportAuthenticator(secret: Data("secret".utf8))
        let token = try authenticator.issueToken(for: SessionTransportTokenClaims(
            sessionID: SessionID(rawValue: "session-1"),
            clientID: ClientID(rawValue: "client-1"),
            leaseEpoch: 1,
            issuedAtMillis: 10,
            expiresAtMillis: 20
        ))
        let server = SessionTransportServer(
            directory: directory,
            authenticator: authenticator,
            leaseEpochProvider: { _ in 1 },
            nowMillis: { 25 }
        )

        XCTAssertThrowsError(try server.connect(SessionTransportConnectRequest(
            sessionID: SessionID(rawValue: "session-1"),
            clientID: ClientID(rawValue: "client-1"),
            leaseEpoch: 1,
            token: token,
            reconnectAfterOutputSeq: nil
        ))) { error in
            XCTAssertEqual(error as? SessionTransportError, .expiredToken(expiresAtMillis: 20, nowMillis: 25))
        }
    }

    private func makeFixture(currentLeaseEpoch: UInt64) throws -> SessionTransportFixture {
        let directory = SessionDirectory()
        let backend = ReplayLogPTYBackend()
        let actor = try directory.provision(
            sessionID: SessionID(rawValue: "session-1"),
            roomID: RoomID(rawValue: "room-1"),
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            initialSize: TerminalSessionSize(cols: 80, rows: 24)
        ) {
            backend
        }
        try actor.start()
        backend.emitOutput(Array("screen".utf8))

        let authenticator = SessionTransportAuthenticator(secret: Data("transport-secret".utf8))
        let fixture = SessionTransportFixture(
            directory: directory,
            backend: backend,
            authenticator: authenticator,
            currentLeaseEpoch: currentLeaseEpoch
        )
        fixture.server = SessionTransportServer(
            directory: directory,
            authenticator: authenticator,
            leaseEpochProvider: { [weak fixture] _ in
                fixture?.currentLeaseEpoch ?? 0
            },
            nowMillis: { 100 }
        )
        return fixture
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

private final class SessionTransportFixture {
    let directory: SessionDirectory
    let backend: ReplayLogPTYBackend
    let authenticator: SessionTransportAuthenticator
    var currentLeaseEpoch: UInt64
    var server: SessionTransportServer!

    init(
        directory: SessionDirectory,
        backend: ReplayLogPTYBackend,
        authenticator: SessionTransportAuthenticator,
        currentLeaseEpoch: UInt64
    ) {
        self.directory = directory
        self.backend = backend
        self.authenticator = authenticator
        self.currentLeaseEpoch = currentLeaseEpoch
    }

    func connectRequest(
        clientID: String,
        leaseEpoch: UInt64,
        reconnectAfterOutputSeq: UInt64? = nil
    ) throws -> SessionTransportConnectRequest {
        let claims = SessionTransportTokenClaims(
            sessionID: SessionID(rawValue: "session-1"),
            clientID: ClientID(rawValue: clientID),
            leaseEpoch: leaseEpoch,
            issuedAtMillis: 90,
            expiresAtMillis: 130
        )
        return SessionTransportConnectRequest(
            sessionID: claims.sessionID,
            clientID: claims.clientID,
            leaseEpoch: leaseEpoch,
            token: try authenticator.issueToken(for: claims),
            reconnectAfterOutputSeq: reconnectAfterOutputSeq
        )
    }
}
