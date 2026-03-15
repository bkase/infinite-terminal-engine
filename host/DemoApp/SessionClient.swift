import Foundation

@MainActor
protocol SessionSurfaceAdapter: AnyObject {
    func ingestOutput(_ text: String)
    func shutdown()
}

enum SessionSurfacePhase: Equatable {
    case connecting
    case live
    case disconnected(String)
    case failed(String)

    var overlayText: String? {
        switch self {
        case .connecting:
            return "Connecting…"
        case .live:
            return nil
        case .disconnected(let reason):
            return "Disconnected: \(reason)"
        case .failed(let reason):
            return "Failed: \(reason)"
        }
    }
}

struct SessionSurfaceState: Equatable {
    let surfaceID: TerminalSurfaceID
    let sessionID: SessionID
    let adapterGeneration: UInt64
    let lastOutputSeq: UInt64
    let phase: SessionSurfacePhase
}

@MainActor
final class SessionClient {
    typealias AdapterFactory = @MainActor (TerminalSurfaceID, UInt64) -> SessionSurfaceAdapter
    typealias ConnectHandler = (SessionTransportConnectRequest) throws -> SessionTransportConnection

    private struct Entry {
        let sessionID: SessionID
        let clientID: ClientID
        var leaseEpoch: UInt64
        var token: String
        var adapterGeneration: UInt64
        var adapter: SessionSurfaceAdapter
        var connection: SessionTransportConnection
        var lastOutputSeq: UInt64
        var phase: SessionSurfacePhase
        var logLines: [String]
    }

    private let connectHandler: ConnectHandler
    private let adapterFactory: AdapterFactory
    private var entriesBySurfaceID: [TerminalSurfaceID: Entry] = [:]
    private var nextAdapterGeneration: UInt64 = 1

    init(
        connectHandler: @escaping ConnectHandler,
        adapterFactory: @escaping AdapterFactory
    ) {
        self.connectHandler = connectHandler
        self.adapterFactory = adapterFactory
    }

    func subscribe(
        surfaceID: TerminalSurfaceID,
        sessionID: SessionID,
        clientID: ClientID,
        leaseEpoch: UInt64,
        token: String
    ) {
        teardown(surfaceID: surfaceID, disconnectReason: "resubscribe", removeState: false)

        let adapterGeneration = nextAdapterGeneration
        nextAdapterGeneration += 1
        let adapter = adapterFactory(surfaceID, adapterGeneration)
        updateState(
            surfaceID: surfaceID,
            sessionID: sessionID,
            adapterGeneration: adapterGeneration,
            lastOutputSeq: 0,
            phase: .connecting
        )

        do {
            let connection = try connectHandler(SessionTransportConnectRequest(
                sessionID: sessionID,
                clientID: clientID,
                leaseEpoch: leaseEpoch,
                token: token,
                reconnectAfterOutputSeq: nil
            ))
            entriesBySurfaceID[surfaceID] = Entry(
                sessionID: sessionID,
                clientID: clientID,
                leaseEpoch: leaseEpoch,
                token: token,
                adapterGeneration: adapterGeneration,
                adapter: adapter,
                connection: connection,
                lastOutputSeq: 0,
                phase: .connecting,
                logLines: ["surface_id=\(surfaceID.rawValue) session_id=\(sessionID.rawValue) action=subscribe adapter_generation=\(adapterGeneration)"]
            )
            processMessages(surfaceID: surfaceID, messages: connection.drainMessages())
        } catch {
            adapter.shutdown()
            updateState(
                surfaceID: surfaceID,
                sessionID: sessionID,
                adapterGeneration: adapterGeneration,
                lastOutputSeq: 0,
                phase: .failed(error.localizedDescription)
            )
        }
    }

    func reconnect(surfaceID: TerminalSurfaceID) {
        guard let entry = entriesBySurfaceID[surfaceID] else { return }
        subscribe(
            surfaceID: surfaceID,
            sessionID: entry.sessionID,
            clientID: entry.clientID,
            leaseEpoch: entry.leaseEpoch,
            token: entry.token
        )
        appendLog(
            surfaceID: surfaceID,
            line: "surface_id=\(surfaceID.rawValue) session_id=\(entry.sessionID.rawValue) action=reconnect previous_output_seq=\(entry.lastOutputSeq)"
        )
    }

    func poll(surfaceID: TerminalSurfaceID) {
        guard let entry = entriesBySurfaceID[surfaceID] else { return }
        processMessages(surfaceID: surfaceID, messages: entry.connection.drainMessages())
    }

    func unsubscribe(surfaceID: TerminalSurfaceID) {
        teardown(surfaceID: surfaceID, disconnectReason: "unsubscribe", removeState: true)
    }

    func state(for surfaceID: TerminalSurfaceID) -> SessionSurfaceState? {
        stateCache[surfaceID]
    }

    func logLines(for surfaceID: TerminalSurfaceID) -> [String] {
        entriesBySurfaceID[surfaceID]?.logLines ?? []
    }

    private func processMessages(surfaceID: TerminalSurfaceID, messages: [SessionTransportMessage]) {
        guard var entry = entriesBySurfaceID[surfaceID] else { return }

        for message in messages {
            switch message {
            case .bootstrap(let bootstrap):
                entry.adapter.ingestOutput(String(decoding: bootstrap.bytes, as: UTF8.self))
                entry.lastOutputSeq = bootstrap.outputSeqEnd
                entry.logLines.append(
                    "surface_id=\(surfaceID.rawValue) session_id=\(entry.sessionID.rawValue) action=bootstrap output_seq=\(bootstrap.outputSeqEnd) adapter_generation=\(entry.adapterGeneration)"
                )
            case .output(let output):
                entry.adapter.ingestOutput(String(decoding: output.bytes, as: UTF8.self))
                entry.lastOutputSeq = output.seqEnd
                entry.logLines.append(
                    "surface_id=\(surfaceID.rawValue) session_id=\(entry.sessionID.rawValue) action=live output_seq=\(output.seqEnd) adapter_generation=\(entry.adapterGeneration)"
                )
            case .status(let status):
                switch status.status {
                case .running:
                    entry.phase = .live
                case .failed:
                    entry.phase = .failed(status.failureReason ?? "session_failed")
                case .exited:
                    entry.phase = .disconnected("session_exited")
                case .provisioning:
                    entry.phase = .connecting
                }
                entry.lastOutputSeq = max(entry.lastOutputSeq, status.outputSeq)
                entry.logLines.append(
                    "surface_id=\(surfaceID.rawValue) session_id=\(entry.sessionID.rawValue) action=status session_status=\(status.status.rawValue) output_seq=\(status.outputSeq) adapter_generation=\(entry.adapterGeneration)"
                )
            case .leaseRevoked(let revoked):
                entry.phase = .disconnected("lease_revoked:\(revoked.currentLeaseEpoch)")
                entry.connection.disconnect(reason: "lease_revoked")
                entry.logLines.append(
                    "surface_id=\(surfaceID.rawValue) session_id=\(entry.sessionID.rawValue) action=lease_revoked current_epoch=\(revoked.currentLeaseEpoch) adapter_generation=\(entry.adapterGeneration)"
                )
            }
        }

        entriesBySurfaceID[surfaceID] = entry
        updateState(
            surfaceID: surfaceID,
            sessionID: entry.sessionID,
            adapterGeneration: entry.adapterGeneration,
            lastOutputSeq: entry.lastOutputSeq,
            phase: entry.phase
        )
    }

    private func teardown(
        surfaceID: TerminalSurfaceID,
        disconnectReason: String,
        removeState: Bool
    ) {
        guard let entry = entriesBySurfaceID.removeValue(forKey: surfaceID) else { return }
        entry.connection.disconnect(reason: disconnectReason)
        entry.adapter.shutdown()
        if removeState {
            stateCache.removeValue(forKey: surfaceID)
        } else {
            updateState(
                surfaceID: surfaceID,
                sessionID: entry.sessionID,
                adapterGeneration: entry.adapterGeneration,
                lastOutputSeq: entry.lastOutputSeq,
                phase: .disconnected(disconnectReason)
            )
        }
    }

    private func updateState(
        surfaceID: TerminalSurfaceID,
        sessionID: SessionID,
        adapterGeneration: UInt64,
        lastOutputSeq: UInt64,
        phase: SessionSurfacePhase
    ) {
        let state = SessionSurfaceState(
            surfaceID: surfaceID,
            sessionID: sessionID,
            adapterGeneration: adapterGeneration,
            lastOutputSeq: lastOutputSeq,
            phase: phase
        )
        stateCache[surfaceID] = state
        if let entry = entriesBySurfaceID[surfaceID] {
            var updated = entry
            updated.phase = phase
            updated.lastOutputSeq = lastOutputSeq
            entriesBySurfaceID[surfaceID] = updated
        }
    }

    private func appendLog(surfaceID: TerminalSurfaceID, line: String) {
        guard var entry = entriesBySurfaceID[surfaceID] else { return }
        entry.logLines.append(line)
        entriesBySurfaceID[surfaceID] = entry
    }

    private var stateCache: [TerminalSurfaceID: SessionSurfaceState] = [:]
}

extension GhosttySurfaceAdapter: SessionSurfaceAdapter {}

@MainActor
final class GhosttySessionManager {
    private final class AdapterRegistry {
        var adaptersBySurfaceID: [TerminalSurfaceID: GhosttySurfaceAdapter] = [:]
    }

    private let client: SessionClient
    private let registry: AdapterRegistry

    init(
        profile: RenderProfile,
        connectHandler: @escaping SessionClient.ConnectHandler
    ) {
        let registry = AdapterRegistry()
        self.registry = registry
        self.client = SessionClient(
            connectHandler: connectHandler,
            adapterFactory: { surfaceID, generation in
                let adapter = GhosttySurfaceAdapter(profile: profile, bootstrap: .empty)
                registry.adaptersBySurfaceID[surfaceID] = adapter
                _ = generation
                return adapter
            }
        )
    }

    func subscribe(
        surfaceID: TerminalSurfaceID,
        sessionID: SessionID,
        clientID: ClientID,
        leaseEpoch: UInt64,
        token: String
    ) {
        client.subscribe(
            surfaceID: surfaceID,
            sessionID: sessionID,
            clientID: clientID,
            leaseEpoch: leaseEpoch,
            token: token
        )
    }

    func reconnect(surfaceID: TerminalSurfaceID) {
        client.reconnect(surfaceID: surfaceID)
    }

    func poll(surfaceID: TerminalSurfaceID) {
        client.poll(surfaceID: surfaceID)
    }

    func unsubscribe(surfaceID: TerminalSurfaceID) {
        client.unsubscribe(surfaceID: surfaceID)
        registry.adaptersBySurfaceID.removeValue(forKey: surfaceID)
    }

    func adapter(for surfaceID: TerminalSurfaceID) -> GhosttySurfaceAdapter? {
        registry.adaptersBySurfaceID[surfaceID]
    }

    func state(for surfaceID: TerminalSurfaceID) -> SessionSurfaceState? {
        client.state(for: surfaceID)
    }
}
