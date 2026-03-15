import CryptoKit
import Foundation

struct SessionTransportConnectRequest: Equatable {
    let sessionID: SessionID
    let clientID: ClientID
    let leaseEpoch: UInt64
    let token: String
    let reconnectAfterOutputSeq: UInt64?
}

struct SessionTransportInputFrame: Equatable {
    let clientInputSeq: UInt64
    let bytes: [UInt8]
}

struct SessionTransportLeaseRevoked: Equatable {
    let previousLeaseEpoch: UInt64
    let currentLeaseEpoch: UInt64
}

enum SessionTransportMessage: Equatable {
    case bootstrap(SessionBootstrap)
    case output(SessionOutputChunk)
    case status(SessionStatusRecord)
    case leaseRevoked(SessionTransportLeaseRevoked)
}

enum SessionTransportResumeMode: String, Equatable {
    case bootstrap
    case replay
    case staleAnchorBootstrap
}

struct SessionTransportTokenClaims: Codable, Equatable {
    let sessionID: SessionID
    let clientID: ClientID
    let leaseEpoch: UInt64
    let issuedAtMillis: UInt64
    let expiresAtMillis: UInt64
}

enum SessionTransportError: Error, Equatable, LocalizedError {
    case malformedToken
    case invalidTokenSignature
    case expiredToken(expiresAtMillis: UInt64, nowMillis: UInt64)
    case tokenLifetimeExceeded(maxLifetimeMillis: UInt64, actualLifetimeMillis: UInt64)
    case sessionMismatch(expected: SessionID, actual: SessionID)
    case clientMismatch(expected: ClientID, actual: ClientID)
    case leaseEpochMismatch(expected: UInt64, actual: UInt64)
    case sessionNotFound(SessionID)
    case roomMembershipRequired(sessionID: SessionID, clientID: ClientID)
    case membershipRevoked(sessionID: SessionID, clientID: ClientID)
    case leaseRevoked(currentLeaseEpoch: UInt64)

    var errorDescription: String? {
        switch self {
        case .malformedToken:
            return "session transport token is malformed"
        case .invalidTokenSignature:
            return "session transport token signature is invalid"
        case .expiredToken(let expiresAtMillis, let nowMillis):
            return "session transport token expired at \(expiresAtMillis); now=\(nowMillis)"
        case .tokenLifetimeExceeded(let maxLifetimeMillis, let actualLifetimeMillis):
            return "session transport token lifetime \(actualLifetimeMillis) exceeds max \(maxLifetimeMillis)"
        case .sessionMismatch(let expected, let actual):
            return "session transport token scoped to session \(actual.rawValue); expected \(expected.rawValue)"
        case .clientMismatch(let expected, let actual):
            return "session transport token scoped to client \(actual.rawValue); expected \(expected.rawValue)"
        case .leaseEpochMismatch(let expected, let actual):
            return "session transport lease epoch \(actual) does not match current epoch \(expected)"
        case .sessionNotFound(let sessionID):
            return "session transport could not find session \(sessionID.rawValue)"
        case .roomMembershipRequired(let sessionID, let clientID):
            return "client \(clientID.rawValue) is not an active room member for session \(sessionID.rawValue)"
        case .membershipRevoked(let sessionID, let clientID):
            return "client \(clientID.rawValue) lost room membership for session \(sessionID.rawValue)"
        case .leaseRevoked(let currentLeaseEpoch):
            return "session transport lease revoked; current epoch is \(currentLeaseEpoch)"
        }
    }
}

struct SessionTransportDiagnostics: Equatable {
    let connectionID: String
    let sessionID: SessionID
    let clientID: ClientID
    let authenticatedLeaseEpoch: UInt64
    let reconnectAfterOutputSeq: UInt64?
    let resumeMode: SessionTransportResumeMode
    let logLines: [String]
}

struct SessionTransportAuthenticator {
    private let key: SymmetricKey
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(secret: Data) {
        self.key = SymmetricKey(data: secret)
    }

    func issueToken(for claims: SessionTransportTokenClaims) throws -> String {
        let payload = try encoder.encode(claims)
        let signature = Data(HMAC<SHA256>.authenticationCode(for: payload, using: key))
        return "\(payload.base64URLEncodedString()).\(signature.base64URLEncodedString())"
    }

    func verifyToken(_ token: String, nowMillis: UInt64) throws -> SessionTransportTokenClaims {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let payload = Data(base64URLEncoded: String(parts[0])),
              let signature = Data(base64URLEncoded: String(parts[1]))
        else {
            throw SessionTransportError.malformedToken
        }

        let expectedSignature = Data(HMAC<SHA256>.authenticationCode(for: payload, using: key))
        guard expectedSignature == signature else {
            throw SessionTransportError.invalidTokenSignature
        }

        let claims = try decoder.decode(SessionTransportTokenClaims.self, from: payload)
        guard claims.expiresAtMillis >= nowMillis else {
            throw SessionTransportError.expiredToken(
                expiresAtMillis: claims.expiresAtMillis,
                nowMillis: nowMillis
            )
        }
        return claims
    }
}

final class SessionTransportServer {
    private let directory: SessionDirectory
    private let authenticator: SessionTransportAuthenticator
    private let leaseEpochProvider: (SessionID) -> UInt64
    private let membershipProvider: (ClientID, SessionID) -> Bool
    private let nowMillis: () -> UInt64
    private let maxTokenLifetimeMillis: UInt64
    private var nextConnectionOrdinal: UInt64 = 1
    private var connectionIDsBySessionID: [SessionID: Set<String>] = [:]
    private var connectionsByID: [String: SessionTransportConnection] = [:]

    init(
        directory: SessionDirectory,
        authenticator: SessionTransportAuthenticator,
        leaseEpochProvider: @escaping (SessionID) -> UInt64,
        membershipProvider: @escaping (ClientID, SessionID) -> Bool = { _, _ in true },
        nowMillis: @escaping () -> UInt64,
        maxTokenLifetimeMillis: UInt64 = 60_000
    ) {
        self.directory = directory
        self.authenticator = authenticator
        self.leaseEpochProvider = leaseEpochProvider
        self.membershipProvider = membershipProvider
        self.nowMillis = nowMillis
        self.maxTokenLifetimeMillis = maxTokenLifetimeMillis
    }

    func connect(_ request: SessionTransportConnectRequest) throws -> SessionTransportConnection {
        do {
            let claims = try authenticator.verifyToken(request.token, nowMillis: nowMillis())
            let tokenLifetimeMillis = claims.expiresAtMillis - claims.issuedAtMillis
            guard tokenLifetimeMillis <= maxTokenLifetimeMillis else {
                throw SessionTransportError.tokenLifetimeExceeded(
                    maxLifetimeMillis: maxTokenLifetimeMillis,
                    actualLifetimeMillis: tokenLifetimeMillis
                )
            }
            guard claims.sessionID == request.sessionID else {
                throw SessionTransportError.sessionMismatch(expected: request.sessionID, actual: claims.sessionID)
            }
            guard claims.clientID == request.clientID else {
                throw SessionTransportError.clientMismatch(expected: request.clientID, actual: claims.clientID)
            }
            guard claims.leaseEpoch == request.leaseEpoch else {
                throw SessionTransportError.leaseEpochMismatch(expected: request.leaseEpoch, actual: claims.leaseEpoch)
            }
            guard membershipProvider(request.clientID, request.sessionID) else {
                throw SessionTransportError.roomMembershipRequired(sessionID: request.sessionID, clientID: request.clientID)
            }

            let currentLeaseEpoch = leaseEpochProvider(request.sessionID)
            guard currentLeaseEpoch == request.leaseEpoch else {
                throw SessionTransportError.leaseEpochMismatch(
                    expected: currentLeaseEpoch,
                    actual: request.leaseEpoch
                )
            }

            guard let session = directory.session(for: request.sessionID) else {
                throw SessionTransportError.sessionNotFound(request.sessionID)
            }

            let bootstrap = try session.subscribe(clientID: request.clientID)
            let state = session.state()
            let connectionID = "session-\(request.sessionID.rawValue)-conn-\(nextConnectionOrdinal)"
            nextConnectionOrdinal += 1

            let statusRecord = Self.makeStatusRecord(from: state)
            var pendingMessages: [SessionTransportMessage]
            let resumeMode: SessionTransportResumeMode
            if let reconnectAfter = request.reconnectAfterOutputSeq {
                if reconnectAfter <= state.outputSeq {
                    pendingMessages = session.outputChunks(after: reconnectAfter).map(SessionTransportMessage.output)
                    pendingMessages.append(.status(statusRecord))
                    resumeMode = .replay
                } else {
                    pendingMessages = [
                        .bootstrap(bootstrap),
                        .status(statusRecord),
                    ]
                    resumeMode = .staleAnchorBootstrap
                }
            } else {
                pendingMessages = [
                    .bootstrap(bootstrap),
                    .status(statusRecord),
                ]
                resumeMode = .bootstrap
            }

            let reconnectAfterDescription = request.reconnectAfterOutputSeq.map(String.init) ?? "none"
            let initialDeliveryCount = session.deliveries(for: request.clientID).count
            var logLines = [
                "connection_id=\(connectionID) session_id=\(request.sessionID.rawValue) client_id=\(request.clientID.rawValue) auth=ok lease_epoch=\(request.leaseEpoch)",
                "connection_id=\(connectionID) resume_mode=\(resumeMode.rawValue) reconnect_after=\(reconnectAfterDescription)",
            ]
            if resumeMode == .staleAnchorBootstrap {
                logLines.append(
                    "connection_id=\(connectionID) stale_anchor=\(request.reconnectAfterOutputSeq ?? 0) current_output_seq=\(state.outputSeq) action=bootstrap"
                )
            }
            logLines.append(contentsOf: pendingMessages.map { Self.describe($0, connectionID: connectionID) })

            let connection = SessionTransportConnection(
                connectionID: connectionID,
                session: session,
                clientID: request.clientID,
                authenticatedLeaseEpoch: request.leaseEpoch,
                initialResumeMode: resumeMode,
                reconnectAfterOutputSeq: request.reconnectAfterOutputSeq,
                initialPendingMessages: pendingMessages,
                initialDeliveryCount: initialDeliveryCount,
                leaseEpochProvider: leaseEpochProvider,
                membershipProvider: membershipProvider,
                initialLogLines: logLines,
                securityLogger: { [weak self] event, level, fields in
                    self?.recordSecurityEvent(event: event, level: level, fields: fields)
                },
                onDisconnect: { [weak self] connectionID, sessionID in
                    self?.removeConnection(connectionID: connectionID, sessionID: sessionID)
                }
            )
            connectionsByID[connectionID] = connection
            connectionIDsBySessionID[request.sessionID, default: []].insert(connectionID)
            Observability.metric(
                "session.transport_connect_total",
                value: 1,
                unit: "count",
                dimensions: [
                    "session_id": request.sessionID.rawValue,
                    "client_id": request.clientID.rawValue,
                    "resume_mode": resumeMode.rawValue,
                ]
            )
            Observability.log(
                domain: "session",
                component: "session-transport",
                event: "transport_connected",
                fields: [
                    "session_id": request.sessionID.rawValue,
                    "client_id": request.clientID.rawValue,
                    "connection_id": connectionID,
                    "resume_mode": resumeMode.rawValue,
                    "lease_epoch": String(request.leaseEpoch),
                ]
            )
            return connection
        } catch let error as SessionTransportError {
            recordConnectDenial(request: request, error: error)
            throw error
        }
    }

    func noteLeaseEpochChanged(for sessionID: SessionID) {
        for connectionID in connectionIDsBySessionID[sessionID, default: []] {
            connectionsByID[connectionID]?.noteLeaseEpochChanged()
        }
    }

    private func removeConnection(connectionID: String, sessionID: SessionID) {
        connectionsByID.removeValue(forKey: connectionID)
        guard var connectionIDs = connectionIDsBySessionID[sessionID] else { return }
        connectionIDs.remove(connectionID)
        if connectionIDs.isEmpty {
            connectionIDsBySessionID.removeValue(forKey: sessionID)
        } else {
            connectionIDsBySessionID[sessionID] = connectionIDs
        }
    }

    private static func makeStatusRecord(from state: SessionActorState) -> SessionStatusRecord {
        SessionStatusRecord(
            status: state.status,
            outputSeq: state.outputSeq,
            exitCode: state.exitCode,
            failureReason: state.failureReason,
            resize: state.resizeReconciliation
        )
    }

    fileprivate static func describe(_ message: SessionTransportMessage, connectionID: String) -> String {
        switch message {
        case .bootstrap(let bootstrap):
            return "connection_id=\(connectionID) direction=s2c type=bootstrap seq_start=\(bootstrap.outputSeqStart) seq_end=\(bootstrap.outputSeqEnd) bytes=\(bootstrap.bytes.count)"
        case .output(let output):
            return "connection_id=\(connectionID) direction=s2c type=output seq_start=\(output.seqStart) seq_end=\(output.seqEnd) bytes=\(output.bytes.count)"
        case .status(let status):
            return "connection_id=\(connectionID) direction=s2c type=status session_status=\(status.status.rawValue) output_seq=\(status.outputSeq)"
        case .leaseRevoked(let revoked):
            return "connection_id=\(connectionID) direction=s2c type=lease_revoked previous_epoch=\(revoked.previousLeaseEpoch) current_epoch=\(revoked.currentLeaseEpoch)"
        }
    }

    private func recordConnectDenial(request: SessionTransportConnectRequest, error: SessionTransportError) {
        recordSecurityEvent(
            event: "session_subscribe_denied",
            level: "error",
            fields: [
                "decision": "deny",
                "failure_class": "policy",
                "session_id": request.sessionID.rawValue,
                "client_id": request.clientID.rawValue,
                "lease_epoch": String(request.leaseEpoch),
                "reason": String(describing: error),
            ]
        )
    }

    private func recordSecurityEvent(
        event: String,
        level: String,
        fields: [String: String]
    ) {
        Observability.log(
            domain: "security",
            component: "session-transport",
            event: event,
            level: level,
            fields: fields
        )
    }
}

final class SessionTransportConnection {
    let connectionID: String

    private let session: SessionActor
    private let clientID: ClientID
    private let authenticatedLeaseEpoch: UInt64
    private let initialResumeMode: SessionTransportResumeMode
    private let reconnectAfterOutputSeq: UInt64?
    private let leaseEpochProvider: (SessionID) -> UInt64
    private let membershipProvider: (ClientID, SessionID) -> Bool

    private var pendingMessages: [SessionTransportMessage]
    private var deliveryCount: Int
    private var didSendLeaseRevoked = false
    private var isDisconnected = false
    private var logLines: [String]
    private let securityLogger: (String, String, [String: String]) -> Void
    private let onDisconnect: (String, SessionID) -> Void

    init(
        connectionID: String,
        session: SessionActor,
        clientID: ClientID,
        authenticatedLeaseEpoch: UInt64,
        initialResumeMode: SessionTransportResumeMode,
        reconnectAfterOutputSeq: UInt64?,
        initialPendingMessages: [SessionTransportMessage],
        initialDeliveryCount: Int,
        leaseEpochProvider: @escaping (SessionID) -> UInt64,
        membershipProvider: @escaping (ClientID, SessionID) -> Bool,
        initialLogLines: [String],
        securityLogger: @escaping (String, String, [String: String]) -> Void,
        onDisconnect: @escaping (String, SessionID) -> Void
    ) {
        self.connectionID = connectionID
        self.session = session
        self.clientID = clientID
        self.authenticatedLeaseEpoch = authenticatedLeaseEpoch
        self.initialResumeMode = initialResumeMode
        self.reconnectAfterOutputSeq = reconnectAfterOutputSeq
        self.pendingMessages = initialPendingMessages
        self.deliveryCount = initialDeliveryCount
        self.leaseEpochProvider = leaseEpochProvider
        self.membershipProvider = membershipProvider
        self.logLines = initialLogLines
        self.securityLogger = securityLogger
        self.onDisconnect = onDisconnect
    }

    func sendInput(_ frame: SessionTransportInputFrame) throws {
        guard membershipProvider(clientID, session.sessionID) else {
            let error = SessionTransportError.membershipRevoked(sessionID: session.sessionID, clientID: clientID)
            recordInputDenied(frame: frame, error: error)
            throw error
        }
        try refreshLeaseState()
        let currentLeaseEpoch = leaseEpochProvider(session.sessionID)
        guard currentLeaseEpoch == authenticatedLeaseEpoch else {
            let error = SessionTransportError.leaseRevoked(currentLeaseEpoch: currentLeaseEpoch)
            recordInputDenied(frame: frame, error: error)
            throw error
        }
        try session.sendInput(frame.bytes)
        recordInputAudit(frame)
        Observability.metric(
            "session.input_bytes",
            value: Double(frame.bytes.count),
            unit: "bytes",
            dimensions: [
                "session_id": session.sessionID.rawValue,
                "client_id": clientID.rawValue,
            ]
        )
        Observability.log(
            domain: "session",
            component: "session-transport",
            event: "input_forwarded",
            fields: [
                "session_id": session.sessionID.rawValue,
                "client_id": clientID.rawValue,
                "connection_id": connectionID,
                "client_input_seq": String(frame.clientInputSeq),
                "bytes": String(frame.bytes.count),
            ]
        )
        logLines.append(
            "connection_id=\(connectionID) direction=c2s type=input client_input_seq=\(frame.clientInputSeq) bytes=\(frame.bytes.count)"
        )
    }

    func drainMessages() -> [SessionTransportMessage] {
        syncLiveDeliveries()
        let messages = pendingMessages
        pendingMessages = []
        return messages
    }

    func refreshLeaseState() throws {
        guard membershipProvider(clientID, session.sessionID) else {
            throw SessionTransportError.membershipRevoked(sessionID: session.sessionID, clientID: clientID)
        }
        let currentLeaseEpoch = leaseEpochProvider(session.sessionID)
        guard currentLeaseEpoch == authenticatedLeaseEpoch else {
            if !didSendLeaseRevoked {
                let revoked = SessionTransportLeaseRevoked(
                    previousLeaseEpoch: authenticatedLeaseEpoch,
                    currentLeaseEpoch: currentLeaseEpoch
                )
                let message = SessionTransportMessage.leaseRevoked(revoked)
                pendingMessages.append(message)
                logLines.append(SessionTransportServer.describe(message, connectionID: connectionID))
                didSendLeaseRevoked = true
                Observability.metric(
                    "session.lease_revoked_total",
                    value: 1,
                    unit: "count",
                    dimensions: [
                        "session_id": session.sessionID.rawValue,
                        "client_id": clientID.rawValue,
                    ]
                )
                Observability.log(
                    domain: "session",
                    component: "session-transport",
                    event: "lease_revoked",
                    level: "error",
                    fields: [
                        "session_id": session.sessionID.rawValue,
                        "client_id": clientID.rawValue,
                        "connection_id": connectionID,
                        "previous_lease_epoch": String(authenticatedLeaseEpoch),
                        "current_lease_epoch": String(currentLeaseEpoch),
                    ]
                )
            }
            throw SessionTransportError.leaseRevoked(currentLeaseEpoch: currentLeaseEpoch)
        }
    }

    func disconnect(reason: String) {
        guard !isDisconnected else { return }
        isDisconnected = true
        session.unsubscribe(clientID: clientID)
        logLines.append("connection_id=\(connectionID) disconnected reason=\(reason)")
        onDisconnect(connectionID, session.sessionID)
    }

    func diagnostics() -> SessionTransportDiagnostics {
        syncLiveDeliveries()
        return SessionTransportDiagnostics(
            connectionID: connectionID,
            sessionID: session.sessionID,
            clientID: clientID,
            authenticatedLeaseEpoch: authenticatedLeaseEpoch,
            reconnectAfterOutputSeq: reconnectAfterOutputSeq,
            resumeMode: initialResumeMode,
            logLines: logLines
        )
    }

    func noteLeaseEpochChanged() {
        try? refreshLeaseState()
    }

    private func syncLiveDeliveries() {
        let deliveries = session.deliveries(for: clientID)
        guard deliveryCount < deliveries.count else { return }
        for delivery in deliveries[deliveryCount...] {
            guard let message = Self.transportMessage(from: delivery) else { continue }
            pendingMessages.append(message)
            logLines.append(SessionTransportServer.describe(message, connectionID: connectionID))
        }
        deliveryCount = deliveries.count
    }

    private static func transportMessage(from delivery: SessionDelivery) -> SessionTransportMessage? {
        switch delivery {
        case .bootstrap:
            return nil
        case .output(let output):
            return .output(output)
        case .status(let status):
            return .status(status)
        }
    }

    private func recordInputDenied(
        frame: SessionTransportInputFrame,
        error: SessionTransportError
    ) {
        let inputKind = Self.isBracketedPaste(frame.bytes) ? "paste" : "keyboard"
        securityLogger(
            "input_denied",
            "error",
            [
                "decision": "deny",
                "failure_class": "policy",
                "session_id": session.sessionID.rawValue,
                "client_id": clientID.rawValue,
                "connection_id": connectionID,
                "client_input_seq": String(frame.clientInputSeq),
                "input_kind": inputKind,
                "bytes": String(frame.bytes.count),
                "reason": String(describing: error),
            ]
        )
        logLines.append(
            "connection_id=\(connectionID) direction=c2s type=input client_input_seq=\(frame.clientInputSeq) bytes=\(frame.bytes.count) rejected=\(String(describing: error))"
        )
    }

    private func recordInputAudit(_ frame: SessionTransportInputFrame) {
        guard Self.isBracketedPaste(frame.bytes) else { return }
        securityLogger(
            "paste_forwarded",
            "info",
            [
                "decision": "allow",
                "failure_class": "policy",
                "session_id": session.sessionID.rawValue,
                "client_id": clientID.rawValue,
                "connection_id": connectionID,
                "client_input_seq": String(frame.clientInputSeq),
                "input_kind": "paste",
                "bytes": String(frame.bytes.count),
            ]
        )
    }

    private static func isBracketedPaste(_ bytes: [UInt8]) -> Bool {
        let start = Array("\u{1B}[200~".utf8)
        let end = Array("\u{1B}[201~".utf8)
        guard bytes.starts(with: start), bytes.count >= end.count else {
            return false
        }
        return Array(bytes.suffix(end.count)) == end
    }
}

private extension Data {
    init?(base64URLEncoded string: String) {
        var padded = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = padded.count % 4
        if remainder != 0 {
            padded.append(String(repeating: "=", count: 4 - remainder))
        }
        self.init(base64Encoded: padded)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
