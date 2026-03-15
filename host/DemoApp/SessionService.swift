import Foundation

struct TerminalSessionSize: Equatable, Codable {
    var cols: Int
    var rows: Int
}

struct SessionResourceLimits: Equatable {
    let maxCols: Int
    let maxRows: Int
    let maxSubscribers: Int
    let maxBufferedOutputBytes: Int

    static let `default` = SessionResourceLimits(
        maxCols: 400,
        maxRows: 200,
        maxSubscribers: 16,
        maxBufferedOutputBytes: 64 * 1024
    )
}

enum SessionActorError: Error, Equatable, LocalizedError {
    case invalidSize(TerminalSessionSize, limits: SessionResourceLimits)
    case subscriberLimitExceeded(limit: Int)
    case backendStartFailed(String)
    case backendResizeFailed(String)
    case backendBootstrapFailed(String)
    case backendWriteFailed(String)
    case bufferedOutputLimitExceeded(limit: Int)
    case sessionNotRunning(SessionID)
    case sessionAlreadyExists(SessionID)
    case sessionNotFound(SessionID)

    var errorDescription: String? {
        switch self {
        case .invalidSize(let size, let limits):
            return "session size \(size.cols)x\(size.rows) exceeds limits \(limits.maxCols)x\(limits.maxRows)"
        case .subscriberLimitExceeded(let limit):
            return "session subscriber limit \(limit) exceeded"
        case .backendStartFailed(let reason):
            return "backend start failed: \(reason)"
        case .backendResizeFailed(let reason):
            return "backend resize failed: \(reason)"
        case .backendBootstrapFailed(let reason):
            return "backend bootstrap failed: \(reason)"
        case .backendWriteFailed(let reason):
            return "backend write failed: \(reason)"
        case .bufferedOutputLimitExceeded(let limit):
            return "session buffered output exceeded limit \(limit) bytes"
        case .sessionNotRunning(let sessionID):
            return "session \(sessionID.rawValue) is not running"
        case .sessionAlreadyExists(let sessionID):
            return "session \(sessionID.rawValue) already exists"
        case .sessionNotFound(let sessionID):
            return "session \(sessionID.rawValue) was not found"
        }
    }
}

struct SessionOutputChunk: Equatable {
    let seqStart: UInt64
    let seqEnd: UInt64
    let bytes: [UInt8]
}

struct SessionStatusRecord: Equatable {
    let status: RoomSessionStatus
    let outputSeq: UInt64
    let exitCode: Int32?
    let failureReason: String?
}

struct SessionBootstrap: Equatable {
    let bytes: [UInt8]
    let outputSeqStart: UInt64
    let outputSeqEnd: UInt64
    let size: TerminalSessionSize
    let status: RoomSessionStatus
    let exitCode: Int32?
    let failureReason: String?

    var outputSeqAnchor: UInt64 {
        outputSeqEnd
    }
}

enum SessionDelivery: Equatable {
    case bootstrap(SessionBootstrap)
    case output(SessionOutputChunk)
    case status(SessionStatusRecord)
}

struct SessionActorState: Equatable {
    let sessionID: SessionID
    let roomID: RoomID
    let surfaceID: TerminalSurfaceID
    let size: TerminalSessionSize
    let bootstrapPolicy: TerminalBootstrapPolicy
    let status: RoomSessionStatus
    let outputSeq: UInt64
    let subscriberIDs: [ClientID]
    let exitCode: Int32?
    let failureReason: String?
}

enum PTYBackendEvent: Equatable {
    case output([UInt8])
    case exited(Int32)
    case failed(String)
}

protocol PTYBackend: AnyObject {
    var eventSink: ((PTYBackendEvent) -> Void)? { get set }

    func start(sessionID: SessionID, initialSize: TerminalSessionSize) throws
    func resize(to size: TerminalSessionSize) throws
    func writeInput(_ bytes: [UInt8]) throws
    func bootstrap() throws -> [UInt8]
    func stop() throws
}

enum ReplayLogEntry: Equatable {
    case start(TerminalSessionSize)
    case resize(TerminalSessionSize)
    case output([UInt8])
    case input([UInt8])
}

final class ReplayLogPTYBackend: PTYBackend {
    var eventSink: ((PTYBackendEvent) -> Void)?

    private(set) var currentSize: TerminalSessionSize?
    private(set) var transcript: [ReplayLogEntry] = []
    private(set) var isStopped = false

    func start(sessionID: SessionID, initialSize: TerminalSessionSize) throws {
        currentSize = initialSize
        transcript.append(.start(initialSize))
    }

    func resize(to size: TerminalSessionSize) throws {
        currentSize = size
        transcript.append(.resize(size))
    }

    func writeInput(_ bytes: [UInt8]) throws {
        transcript.append(.input(bytes))
    }

    func bootstrap() throws -> [UInt8] {
        transcript.reduce(into: [UInt8]()) { bytes, entry in
            if case .output(let output) = entry {
                bytes.append(contentsOf: output)
            }
        }
    }

    func stop() throws {
        isStopped = true
    }

    func emitOutput(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        transcript.append(.output(bytes))
        eventSink?(.output(bytes))
    }

    func emitExit(_ code: Int32) {
        eventSink?(.exited(code))
    }

    func emitFailure(_ reason: String) {
        eventSink?(.failed(reason))
    }

    func transcriptLines() -> [String] {
        transcript.map { entry in
            switch entry {
            case .start(let size):
                return "start size=\(size.cols)x\(size.rows)"
            case .resize(let size):
                return "resize size=\(size.cols)x\(size.rows)"
            case .output(let bytes):
                return "output bytes=\(bytes.count) text=\(String(decoding: bytes, as: UTF8.self).debugDescription)"
            case .input(let bytes):
                return "input bytes=\(bytes.count) text=\(String(decoding: bytes, as: UTF8.self).debugDescription)"
            }
        }
    }
}

final class SessionActor {
    let sessionID: SessionID
    let roomID: RoomID
    let surfaceID: TerminalSurfaceID
    let bootstrapPolicy: TerminalBootstrapPolicy

    private(set) var size: TerminalSessionSize
    private(set) var status: RoomSessionStatus = .provisioning
    private(set) var outputSeq: UInt64 = 0
    private(set) var exitCode: Int32?
    private(set) var failureReason: String?

    private let backend: PTYBackend
    private let resourceLimits: SessionResourceLimits
    private var subscriberIDs = Set<ClientID>()
    private var deliveriesByClientID: [ClientID: [SessionDelivery]] = [:]
    private var outputHistory: [SessionOutputChunk] = []
    private var bufferedOutputBytes = 0

    init(
        sessionID: SessionID,
        roomID: RoomID,
        surfaceID: TerminalSurfaceID,
        initialSize: TerminalSessionSize,
        bootstrapPolicy: TerminalBootstrapPolicy = .redraw,
        backend: PTYBackend,
        resourceLimits: SessionResourceLimits = .default
    ) throws {
        self.sessionID = sessionID
        self.roomID = roomID
        self.surfaceID = surfaceID
        self.size = initialSize
        self.bootstrapPolicy = bootstrapPolicy
        self.backend = backend
        self.resourceLimits = resourceLimits

        try Self.validate(size: initialSize, limits: resourceLimits)
        backend.eventSink = { [weak self] event in
            self?.handleBackendEvent(event)
        }
    }

    func start() throws {
        do {
            try backend.start(sessionID: sessionID, initialSize: size)
        } catch {
            let message = error.localizedDescription
            transitionToFailed(reason: "backend_start_failed: \(message)")
            throw SessionActorError.backendStartFailed(message)
        }
        status = .running
        failureReason = nil
        exitCode = nil
        broadcast(.status(currentStatusRecord()))
    }

    func resize(to newSize: TerminalSessionSize) throws {
        try Self.validate(size: newSize, limits: resourceLimits)
        size = newSize
        guard status == .running else { return }
        do {
            try backend.resize(to: newSize)
        } catch {
            let message = error.localizedDescription
            transitionToFailed(reason: "backend_resize_failed: \(message)")
            throw SessionActorError.backendResizeFailed(message)
        }
    }

    func sendInput(_ bytes: [UInt8]) throws {
        guard status == .running else {
            throw SessionActorError.sessionNotRunning(sessionID)
        }
        do {
            try backend.writeInput(bytes)
        } catch {
            let message = error.localizedDescription
            transitionToFailed(reason: "backend_write_failed: \(message)")
            throw SessionActorError.backendWriteFailed(message)
        }
    }

    func subscribe(clientID: ClientID) throws -> SessionBootstrap {
        if !subscriberIDs.contains(clientID),
           subscriberIDs.count >= resourceLimits.maxSubscribers
        {
            throw SessionActorError.subscriberLimitExceeded(limit: resourceLimits.maxSubscribers)
        }
        subscriberIDs.insert(clientID)

        let bootstrapBytes: [UInt8]
        do {
            bootstrapBytes = try backend.bootstrap()
        } catch {
            let message = error.localizedDescription
            transitionToFailed(reason: "backend_bootstrap_failed: \(message)")
            throw SessionActorError.backendBootstrapFailed(message)
        }

        let bootstrap = SessionBootstrap(
            bytes: bootstrapBytes,
            outputSeqStart: outputHistory.first?.seqStart ?? 0,
            outputSeqEnd: outputSeq,
            size: size,
            status: status,
            exitCode: exitCode,
            failureReason: failureReason
        )
        deliveriesByClientID[clientID, default: []].append(.bootstrap(bootstrap))
        deliveriesByClientID[clientID, default: []].append(.status(currentStatusRecord()))
        return bootstrap
    }

    func unsubscribe(clientID: ClientID) {
        subscriberIDs.remove(clientID)
    }

    func stop() throws {
        try backend.stop()
    }

    func state() -> SessionActorState {
        SessionActorState(
            sessionID: sessionID,
            roomID: roomID,
            surfaceID: surfaceID,
            size: size,
            bootstrapPolicy: bootstrapPolicy,
            status: status,
            outputSeq: outputSeq,
            subscriberIDs: subscriberIDs.sorted { $0.rawValue < $1.rawValue },
            exitCode: exitCode,
            failureReason: failureReason
        )
    }

    func deliveries(for clientID: ClientID) -> [SessionDelivery] {
        deliveriesByClientID[clientID, default: []]
    }

    func outputChunks() -> [SessionOutputChunk] {
        outputHistory
    }

    func outputChunks(after outputSeq: UInt64) -> [SessionOutputChunk] {
        outputHistory.compactMap { chunk in
            guard chunk.seqEnd > outputSeq else {
                return nil
            }
            guard chunk.seqStart <= outputSeq else {
                return chunk
            }

            let sliceOffset = Int(outputSeq - chunk.seqStart + 1)
            let slicedBytes = Array(chunk.bytes[sliceOffset...])
            return SessionOutputChunk(
                seqStart: outputSeq + 1,
                seqEnd: chunk.seqEnd,
                bytes: slicedBytes
            )
        }
    }

    private static func validate(size: TerminalSessionSize, limits: SessionResourceLimits) throws {
        guard
            size.cols > 0,
            size.rows > 0,
            size.cols <= limits.maxCols,
            size.rows <= limits.maxRows
        else {
            throw SessionActorError.invalidSize(size, limits: limits)
        }
    }

    private func handleBackendEvent(_ event: PTYBackendEvent) {
        switch event {
        case .output(let bytes):
            guard status == .running, !bytes.isEmpty else { return }
            let nextBufferedBytes = bufferedOutputBytes + bytes.count
            guard nextBufferedBytes <= resourceLimits.maxBufferedOutputBytes else {
                transitionToFailed(reason: "buffered_output_limit_exceeded")
                return
            }
            let chunk = SessionOutputChunk(
                seqStart: outputSeq + 1,
                seqEnd: outputSeq + UInt64(bytes.count),
                bytes: bytes
            )
            outputSeq = chunk.seqEnd
            outputHistory.append(chunk)
            bufferedOutputBytes = nextBufferedBytes
            broadcast(.output(chunk))
        case .exited(let code):
            guard status == .running || status == .provisioning else { return }
            status = .exited
            exitCode = code
            failureReason = nil
            broadcast(.status(currentStatusRecord()))
        case .failed(let reason):
            transitionToFailed(reason: reason)
        }
    }

    private func transitionToFailed(reason: String) {
        status = .failed
        failureReason = reason
        exitCode = nil
        broadcast(.status(currentStatusRecord()))
    }

    private func currentStatusRecord() -> SessionStatusRecord {
        SessionStatusRecord(
            status: status,
            outputSeq: outputSeq,
            exitCode: exitCode,
            failureReason: failureReason
        )
    }

    private func broadcast(_ delivery: SessionDelivery) {
        for clientID in subscriberIDs {
            deliveriesByClientID[clientID, default: []].append(delivery)
        }
    }
}

final class SessionDirectory {
    private var sessionsByID: [SessionID: SessionActor] = [:]

    func provision(
        sessionID: SessionID,
        roomID: RoomID,
        surfaceID: TerminalSurfaceID,
        initialSize: TerminalSessionSize,
        bootstrapPolicy: TerminalBootstrapPolicy = .redraw,
        resourceLimits: SessionResourceLimits = .default,
        backendFactory: () -> PTYBackend
    ) throws -> SessionActor {
        guard sessionsByID[sessionID] == nil else {
            throw SessionActorError.sessionAlreadyExists(sessionID)
        }
        let actor = try SessionActor(
            sessionID: sessionID,
            roomID: roomID,
            surfaceID: surfaceID,
            initialSize: initialSize,
            bootstrapPolicy: bootstrapPolicy,
            backend: backendFactory(),
            resourceLimits: resourceLimits
        )
        sessionsByID[sessionID] = actor
        return actor
    }

    func session(for sessionID: SessionID) -> SessionActor? {
        sessionsByID[sessionID]
    }

    func remove(sessionID: SessionID) throws {
        guard let actor = sessionsByID.removeValue(forKey: sessionID) else {
            throw SessionActorError.sessionNotFound(sessionID)
        }
        try actor.stop()
    }

    func activeSessionIDs() -> [SessionID] {
        sessionsByID.keys.sorted { $0.rawValue < $1.rawValue }
    }
}
