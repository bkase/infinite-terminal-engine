import Foundation
import XCTest
@testable import DemoApp

final class SessionSecurityTests: XCTestCase {
    override func tearDown() {
        Observability.sink = nil
        super.tearDown()
    }

    func testSubscribeRejectsClientWithoutRoomMembershipAndEmitsSecurityAudit() throws {
        let fixture = try makeFixture()
        fixture.isMember = false
        let recorder = ObservabilityRecorder()
        Observability.sink = recorder

        XCTAssertThrowsError(try fixture.server.connect(try fixture.connectRequest(clientID: "client-1", leaseEpoch: 1))) { error in
            XCTAssertEqual(
                error as? SessionTransportError,
                .roomMembershipRequired(sessionID: SessionID(rawValue: "session-1"), clientID: ClientID(rawValue: "client-1"))
            )
        }

        let audit = try XCTUnwrap(recorder.logs.last)
        XCTAssertEqual(audit.domain, "security")
        XCTAssertEqual(audit.event, "session_subscribe_denied")
        XCTAssertEqual(audit.fields["decision"], "deny")
        XCTAssertEqual(audit.fields["client_id"], "client-1")
        XCTAssertEqual(audit.fields["session_id"], "session-1")
    }

    func testMembershipRevocationRejectsInputAndEmitsSecurityAudit() throws {
        let fixture = try makeFixture()
        let recorder = ObservabilityRecorder()
        Observability.sink = recorder
        let connection = try fixture.server.connect(try fixture.connectRequest(clientID: "client-1", leaseEpoch: 1))
        _ = connection.drainMessages()

        fixture.isMember = false
        XCTAssertThrowsError(try connection.sendInput(SessionTransportInputFrame(
            clientInputSeq: 1,
            bytes: Array("ls\n".utf8)
        ))) { error in
            XCTAssertEqual(
                error as? SessionTransportError,
                .membershipRevoked(sessionID: SessionID(rawValue: "session-1"), clientID: ClientID(rawValue: "client-1"))
            )
        }

        let audit = try XCTUnwrap(recorder.logs.last)
        XCTAssertEqual(audit.domain, "security")
        XCTAssertEqual(audit.event, "input_denied")
        XCTAssertEqual(audit.fields["decision"], "deny")
        XCTAssertEqual(audit.fields["input_kind"], "keyboard")
        XCTAssertEqual(audit.fields["client_input_seq"], "1")
    }

    func testBracketedPasteInputProducesAuditableAllowLog() throws {
        let fixture = try makeFixture()
        let recorder = ObservabilityRecorder()
        Observability.sink = recorder
        let connection = try fixture.server.connect(try fixture.connectRequest(clientID: "client-1", leaseEpoch: 1))
        _ = connection.drainMessages()

        try connection.sendInput(SessionTransportInputFrame(
            clientInputSeq: 7,
            bytes: Array("\u{1B}[200~hello\u{1B}[201~".utf8)
        ))

        let audit = try XCTUnwrap(recorder.logs.first(where: { $0.event == "paste_forwarded" }))
        XCTAssertEqual(audit.domain, "security")
        XCTAssertEqual(audit.fields["decision"], "allow")
        XCTAssertEqual(audit.fields["input_kind"], "paste")
        XCTAssertEqual(audit.fields["client_input_seq"], "7")
    }

    func testExcessiveTokenLifetimeIsRejected() throws {
        let fixture = try makeFixture()
        let recorder = ObservabilityRecorder()
        Observability.sink = recorder
        let longLivedToken = try fixture.authenticator.issueToken(for: SessionTransportTokenClaims(
            sessionID: SessionID(rawValue: "session-1"),
            clientID: ClientID(rawValue: "client-1"),
            leaseEpoch: 1,
            issuedAtMillis: 0,
            expiresAtMillis: 120_001
        ))

        XCTAssertThrowsError(try fixture.server.connect(SessionTransportConnectRequest(
            sessionID: SessionID(rawValue: "session-1"),
            clientID: ClientID(rawValue: "client-1"),
            leaseEpoch: 1,
            token: longLivedToken,
            reconnectAfterOutputSeq: nil
        ))) { error in
            XCTAssertEqual(
                error as? SessionTransportError,
                .tokenLifetimeExceeded(maxLifetimeMillis: 60_000, actualLifetimeMillis: 120_001)
            )
        }

        let audit = try XCTUnwrap(recorder.logs.last)
        XCTAssertEqual(audit.event, "session_subscribe_denied")
        XCTAssertEqual(audit.fields["decision"], "deny")
        XCTAssertEqual(audit.fields["reason"], "tokenLifetimeExceeded(maxLifetimeMillis: 60000, actualLifetimeMillis: 120001)")
    }

    private func makeFixture() throws -> SessionSecurityFixture {
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
        let fixture = SessionSecurityFixture(authenticator: authenticator)
        fixture.server = SessionTransportServer(
            directory: directory,
            authenticator: authenticator,
            leaseEpochProvider: { _ in 1 },
            membershipProvider: { [weak fixture] _, _ in
                fixture?.isMember ?? false
            },
            nowMillis: { 100 }
        )
        return fixture
    }
}

private final class SessionSecurityFixture {
    let authenticator: SessionTransportAuthenticator
    var isMember = true
    var server: SessionTransportServer!

    init(authenticator: SessionTransportAuthenticator) {
        self.authenticator = authenticator
    }

    func connectRequest(clientID: String, leaseEpoch: UInt64) throws -> SessionTransportConnectRequest {
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
            reconnectAfterOutputSeq: nil
        )
    }
}
