import Foundation

enum SurfaceLifecyclePhase: String, Equatable {
    case provisioning
    case attached
    case disconnected
    case degraded
    case error
    case closing
}

struct SurfaceLifecycleState: Equatable {
    let surfaceID: TerminalSurfaceID
    let sessionID: SessionID?
    let roomState: DurableSurfaceState?
    let sessionStatus: RoomSessionStatus?
    let clientPhases: [SessionSurfacePhase]
    let phase: SurfaceLifecyclePhase
}

@MainActor
final class SurfaceLifecycleCoordinator {
    private let gateway: RoomGateway
    private let actor: RoomActor
    private let sessionDirectory: SessionDirectory
    private let resizeCoordinator: SessionResizeCoordinator
    private let backendFactory: (SessionID) -> PTYBackend

    private var clientsBySurfaceID: [TerminalSurfaceID: [SessionClient]] = [:]
    private var statesBySurfaceID: [TerminalSurfaceID: SurfaceLifecycleState] = [:]
    private var logLinesBySurfaceID: [TerminalSurfaceID: [String]] = [:]

    init(
        actor: RoomActor,
        gateway: RoomGateway,
        sessionDirectory: SessionDirectory,
        resizeCoordinator: SessionResizeCoordinator,
        backendFactory: @escaping (SessionID) -> PTYBackend
    ) {
        self.actor = actor
        self.gateway = gateway
        self.sessionDirectory = sessionDirectory
        self.resizeCoordinator = resizeCoordinator
        self.backendFactory = backendFactory
    }

    @discardableResult
    func createSurface(
        surfaceID: TerminalSurfaceID,
        sessionID: SessionID,
        clientID: ClientID,
        cols: Int,
        rows: Int,
        profileID: String
    ) throws -> SurfaceLifecycleState {
        let create = try gateway.submit(RoomOpRecord(
            schemaVersion: .v1,
            roomID: actor.snapshot.roomID,
            roomSeq: nil,
            opID: RoomOpID(rawValue: "create-\(surfaceID.rawValue)"),
            clientID: clientID,
            submittedAtMillis: 100,
            payload: .createSurface(CreateSurfaceOp(
                surfaceID: surfaceID,
                xWorld: 0,
                yWorld: 0,
                cols: cols,
                rows: rows,
                profileID: profileID,
                terminalTemplate: nil
            ))
        ), from: clientID)
        _ = create
        appendLog(surfaceID: surfaceID, line: "surface_id=\(surfaceID.rawValue) action=create")
        updateLifecycle(surfaceID: surfaceID)

        let session = try sessionDirectory.provision(
            sessionID: sessionID,
            roomID: actor.snapshot.roomID,
            surfaceID: surfaceID,
            initialSize: TerminalSessionSize(cols: cols, rows: rows)
        ) {
            backendFactory(sessionID)
        }
        try session.start()
        appendLog(surfaceID: surfaceID, line: "surface_id=\(surfaceID.rawValue) session_id=\(sessionID.rawValue) action=session_started")

        let attach = try gateway.submit(RoomOpRecord(
            schemaVersion: .v1,
            roomID: actor.snapshot.roomID,
            roomSeq: nil,
            opID: RoomOpID(rawValue: "attach-\(surfaceID.rawValue)"),
            clientID: clientID,
            submittedAtMillis: 101,
            payload: .attachSession(AttachSessionOp(surfaceID: surfaceID, sessionID: sessionID))
        ), from: clientID)
        resizeCoordinator.apply(attach)
        appendLog(surfaceID: surfaceID, line: "surface_id=\(surfaceID.rawValue) session_id=\(sessionID.rawValue) action=attach")
        return updateLifecycle(surfaceID: surfaceID)
    }

    @MainActor
    func subscribeSurface(
        surfaceID: TerminalSurfaceID,
        client: SessionClient,
        clientID: ClientID,
        leaseEpoch: UInt64,
        token: String
    ) {
        guard let roomSurface = actor.snapshot.surfaces.first(where: { $0.id == surfaceID }),
              let sessionID = roomSurface.sessionID else { return }
        clientsBySurfaceID[surfaceID, default: []].append(client)
        client.subscribe(
            surfaceID: surfaceID,
            sessionID: sessionID,
            clientID: clientID,
            leaseEpoch: leaseEpoch,
            token: token
        )
        appendLog(surfaceID: surfaceID, line: "surface_id=\(surfaceID.rawValue) session_id=\(sessionID.rawValue) action=subscribe client_id=\(clientID.rawValue)")
        _ = updateLifecycle(surfaceID: surfaceID)
    }

    @MainActor
    func pollClients(surfaceID: TerminalSurfaceID) {
        for client in clientsBySurfaceID[surfaceID, default: []] {
            client.poll(surfaceID: surfaceID)
        }
        _ = updateLifecycle(surfaceID: surfaceID)
    }

    @discardableResult
    func closeSurface(surfaceID: TerminalSurfaceID, clientID: ClientID) throws -> SurfaceLifecycleState? {
        guard let existing = statesBySurfaceID[surfaceID] else { return nil }
        statesBySurfaceID[surfaceID] = SurfaceLifecycleState(
            surfaceID: existing.surfaceID,
            sessionID: existing.sessionID,
            roomState: existing.roomState,
            sessionStatus: existing.sessionStatus,
            clientPhases: existing.clientPhases,
            phase: .closing
        )
        appendLog(surfaceID: surfaceID, line: "surface_id=\(surfaceID.rawValue) action=closing")

        if let sessionID = existing.sessionID {
            try sessionDirectory.remove(sessionID: sessionID)
        }
        for client in clientsBySurfaceID.removeValue(forKey: surfaceID) ?? [] {
            client.unsubscribe(surfaceID: surfaceID)
        }
        _ = try gateway.submit(RoomOpRecord(
            schemaVersion: .v1,
            roomID: actor.snapshot.roomID,
            roomSeq: nil,
            opID: RoomOpID(rawValue: "close-\(surfaceID.rawValue)"),
            clientID: clientID,
            submittedAtMillis: 102,
            payload: .closeSurface(CloseSurfaceOp(surfaceID: surfaceID))
        ), from: clientID)
        appendLog(surfaceID: surfaceID, line: "surface_id=\(surfaceID.rawValue) action=closed")
        return statesBySurfaceID.removeValue(forKey: surfaceID)
    }

    @discardableResult
    func updateLifecycle(surfaceID: TerminalSurfaceID) -> SurfaceLifecycleState {
        let roomSurface = actor.snapshot.surfaces.first(where: { $0.id == surfaceID })
        let session = roomSurface?.sessionID.flatMap(sessionDirectory.session(for:))
        let clientPhases = clientsBySurfaceID[surfaceID, default: []].compactMap {
            $0.state(for: surfaceID)?.phase
        }

        let phase: SurfaceLifecyclePhase
        if roomSurface == nil {
            phase = .closing
        } else if session?.state().status == .failed {
            phase = .error
        } else if clientPhases.contains(where: {
            if case .failed = $0 { return true }
            if case .disconnected = $0 { return true }
            return false
        }) {
            phase = .degraded
        } else if roomSurface?.state == .attached, session?.state().status == .running {
            phase = .attached
        } else if roomSurface?.state == .disconnected || session?.state().status == .exited {
            phase = .disconnected
        } else {
            phase = .provisioning
        }

        let state = SurfaceLifecycleState(
            surfaceID: surfaceID,
            sessionID: roomSurface?.sessionID,
            roomState: roomSurface?.state,
            sessionStatus: session?.state().status,
            clientPhases: clientPhases,
            phase: phase
        )
        statesBySurfaceID[surfaceID] = state
        appendLog(
            surfaceID: surfaceID,
            line: "surface_id=\(surfaceID.rawValue) lifecycle=\(phase.rawValue) room_state=\(roomSurface?.state.rawValue ?? "none") session_status=\(session?.state().status.rawValue ?? "none") client_count=\(clientPhases.count)"
        )
        return state
    }

    func state(for surfaceID: TerminalSurfaceID) -> SurfaceLifecycleState? {
        statesBySurfaceID[surfaceID]
    }

    func logLines(for surfaceID: TerminalSurfaceID) -> [String] {
        logLinesBySurfaceID[surfaceID, default: []]
    }

    private func appendLog(surfaceID: TerminalSurfaceID, line: String) {
        logLinesBySurfaceID[surfaceID, default: []].append(line)
    }
}
