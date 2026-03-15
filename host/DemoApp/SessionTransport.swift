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
    case sessionMismatch(expected: SessionID, actual: SessionID)
    case clientMismatch(expected: ClientID, actual: ClientID)
    case leaseEpochMismatch(expected: UInt64, actual: UInt64)
    case sessionNotFound(SessionID)
    case leaseRevoked(currentLeaseEpoch: UInt64)

    var errorDescription: String? {
        switch self {
        case .malformedToken:
            return "session transport token is malformed"
        case .invalidTokenSignature:
            return "session transport token signature is invalid"
        case .expiredToken(let expiresAtMillis, let nowMillis):
            return "session transport token expired at \(expiresAtMillis); now=\(nowMillis)"
        case .sessionMismatch(let expected, let actual):
            return "session transport token scoped to session \(actual.rawValue); expected \(expected.rawValue)"
        case .clientMismatch(let expected, let actual):
            return "session transport token scoped to client \(actual.rawValue); expected \(expected.rawValue)"
        case .leaseEpochMismatch(let expected, let actual):
            return "session transport lease epoch \(actual) does not match current epoch \(expected)"
        case .sessionNotFound(let sessionID):
            return "session transport could not find session \(sessionID.rawValue)"
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
    private let nowMillis: () -> UInt64
    private var nextConnectionOrdinal: UInt64 = 1
    private var connectionIDsBySessionID: [SessionID: Set<String>] = [:]
    private var connectionsByID: [String: SessionTransportConnection] = [:]

    init(
        directory: SessionDirectory,
        authenticator: SessionTransportAuthenticator,
        leaseEpochProvider: @escaping (SessionID) -> UInt64,
        nowMillis: @escaping () -> UInt64
    ) {
        self.directory = directory
        self.authenticator = authenticator
        self.leaseEpochProvider = leaseEpochProvider
        self.nowMillis = nowMillis
    }

    func connect(_ request: SessionTransportConnectRequest) throws -> SessionTransportConnection {
        let claims = try authenticator.verifyToken(request.token, nowMillis: nowMillis())
        guard claims.sessionID == request.sessionID else {
            throw SessionTransportError.sessionMismatch(expected: request.sessionID, actual: claims.sessionID)
        }
        guard claims.clientID == request.clientID else {
            throw SessionTransportError.clientMismatch(expected: request.clientID, actual: claims.clientID)
        }
        guard claims.leaseEpoch == request.leaseEpoch else {
            throw SessionTransportError.leaseEpochMismatch(expected: request.leaseEpoch, actual: claims.leaseEpoch)
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
            initialLogLines: logLines,
            onDisconnect: { [weak self] connectionID, sessionID in
                self?.removeConnection(connectionID: connectionID, sessionID: sessionID)
            }
        )
        connectionsByID[connectionID] = connection
        connectionIDsBySessionID[request.sessionID, default: []].insert(connectionID)
        return connection
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
            failureReason: state.failureReason
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
}

final class SessionTransportConnection {
    let connectionID: String

    private let session: SessionActor
    private let clientID: ClientID
    private let authenticatedLeaseEpoch: UInt64
    private let initialResumeMode: SessionTransportResumeMode
    private let reconnectAfterOutputSeq: UInt64?
    private let leaseEpochProvider: (SessionID) -> UInt64

    private var pendingMessages: [SessionTransportMessage]
    private var deliveryCount: Int
    private var didSendLeaseRevoked = false
    private var isDisconnected = false
    private var logLines: [String]
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
        initialLogLines: [String],
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
        self.logLines = initialLogLines
        self.onDisconnect = onDisconnect
    }

    func sendInput(_ frame: SessionTransportInputFrame) throws {
        try refreshLeaseState()
        let currentLeaseEpoch = leaseEpochProvider(session.sessionID)
        guard currentLeaseEpoch == authenticatedLeaseEpoch else {
            throw SessionTransportError.leaseRevoked(currentLeaseEpoch: currentLeaseEpoch)
        }
        try session.sendInput(frame.bytes)
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
