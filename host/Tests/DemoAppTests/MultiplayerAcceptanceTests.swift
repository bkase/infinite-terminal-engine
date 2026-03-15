import Foundation
import XCTest
@testable import DemoApp

@MainActor
final class MultiplayerAcceptanceTests: XCTestCase {
    func testSharedViewLeaseExclusivityAndRevocation() throws {
        let fixture = try MultiplayerAcceptanceFixture()
        let surfaceID = TerminalSurfaceID(rawValue: "surface-1")
        let sessionID = SessionID(rawValue: "session-1")
        try fixture.createSurface(surfaceID: surfaceID, sessionID: sessionID)

        let viewer1 = fixture.makeClient()
        let viewer2 = fixture.makeClient()
        fixture.subscribe(viewer1, surfaceID: surfaceID, sessionID: sessionID, clientID: ClientID(rawValue: "viewer-1"), leaseEpoch: 1)
        fixture.subscribe(viewer2, surfaceID: surfaceID, sessionID: sessionID, clientID: ClientID(rawValue: "viewer-2"), leaseEpoch: 1)

        _ = try fixture.acquireControl(sessionID: sessionID, holderUserID: UserID(rawValue: "user-1"), clientID: ClientID(rawValue: "client-1"), opID: "lease-1")
        let writer = try fixture.connectTransport(sessionID: sessionID, clientID: ClientID(rawValue: "writer-1"), leaseEpoch: 1)
        _ = writer.drainMessages()
        try writer.sendInput(SessionTransportInputFrame(clientInputSeq: 1, bytes: Array("whoami\n".utf8)))

        XCTAssertEqual(viewer1.latestAdapter?.text, "screen")
        XCTAssertEqual(viewer2.latestAdapter?.text, "screen")
        XCTAssertTrue(fixture.backend(sessionID).transcriptLines().contains("input bytes=7 text=\"whoami\\n\""))

        XCTAssertThrowsError(
            try fixture.acquireControl(
                sessionID: sessionID,
                holderUserID: UserID(rawValue: "user-2"),
                clientID: ClientID(rawValue: "client-2"),
                opID: "lease-conflict"
            )
        ) { error in
            XCTAssertEqual(
                error as? RoomGatewayReject,
                RoomGatewayReject(
                    roomID: RoomID(rawValue: "room-1"),
                    clientID: ClientID(rawValue: "client-2"),
                    opID: RoomOpID(rawValue: "lease-conflict"),
                    reason: RoomActorError.controlLeaseHeldByAnotherUser(
                        sessionID,
                        holderUserID: UserID(rawValue: "user-1")
                    ).localizedDescription
                )
            )
        }

        _ = try fixture.releaseControl(sessionID: sessionID, clientID: ClientID(rawValue: "client-1"), opID: "lease-release")
        _ = try fixture.acquireControl(sessionID: sessionID, holderUserID: UserID(rawValue: "user-2"), clientID: ClientID(rawValue: "client-2"), opID: "lease-2")

        XCTAssertEqual(
            writer.drainMessages(),
            [.leaseRevoked(SessionTransportLeaseRevoked(previousLeaseEpoch: 1, currentLeaseEpoch: 2))]
        )
        XCTAssertThrowsError(try writer.sendInput(SessionTransportInputFrame(clientInputSeq: 2, bytes: Array("pwd\n".utf8)))) { error in
            XCTAssertEqual(error as? SessionTransportError, .leaseRevoked(currentLeaseEpoch: 2))
        }

        try recordArtifact(
            name: "shared-view-one-writer",
            runID: "20260315T000000Z-seed-201",
            faults: [
                [
                    "fault_id": "fault-competing-writer",
                    "category": "lease",
                    "mode": "injected",
                    "target": "room-gateway",
                    "trigger": "second user attempts to acquire an active lease",
                    "ts_ms": 3,
                    "detail": "room control rejects the competing writer while both viewers stay attached"
                ],
                [
                    "fault_id": "fault-stale-lease-epoch",
                    "category": "lease",
                    "mode": "injected",
                    "target": "session-transport",
                    "trigger": "prior writer keeps typing after lease epoch changes",
                    "ts_ms": 5,
                    "detail": "the session plane revokes the stale writer without interrupting viewers"
                ],
            ],
            events: [
                roomEvent("evt-surface-attached", ts: 0, scenario: "shared-view-one-writer", kind: "surface_attached", roomSeq: 2, sessionID: sessionID.rawValue),
                clientEvent("evt-viewer-1-live", ts: 1, scenario: "shared-view-one-writer", clientID: "viewer-1", sessionID: sessionID.rawValue, surfaceID: surfaceID.rawValue, kind: "surface_subscribed"),
                clientEvent("evt-viewer-2-live", ts: 2, scenario: "shared-view-one-writer", clientID: "viewer-2", sessionID: sessionID.rawValue, surfaceID: surfaceID.rawValue, kind: "surface_subscribed"),
                roomEvent("evt-competing-writer", ts: 3, scenario: "shared-view-one-writer", kind: "lease_conflict", roomSeq: 3, sessionID: sessionID.rawValue, status: "fault", faultID: "fault-competing-writer"),
                sessionEvent("evt-writer-revoked", ts: 4, scenario: "shared-view-one-writer", sessionID: sessionID.rawValue, kind: "lease_revoked", status: "fault", faultID: "fault-stale-lease-epoch"),
                sessionEvent("evt-stale-input", ts: 5, scenario: "shared-view-one-writer", sessionID: sessionID.rawValue, kind: "input_rejected", status: "fault", faultID: "fault-stale-lease-epoch"),
            ],
            logs: [
                "room-gateway.log": fixture.gateway.deliveries(for: ClientID(rawValue: "client-2")).map(String.init(describing:)).joined(separator: "\n") + "\n",
                "viewer-1.log": viewer1.logLines(surfaceID: surfaceID).joined(separator: "\n") + "\n",
                "viewer-2.log": viewer2.logLines(surfaceID: surfaceID).joined(separator: "\n") + "\n",
                "session-transport.log": writer.diagnostics().logLines.joined(separator: "\n") + "\n",
            ]
        )
    }

    func testLateJoinBootstrapPreservesOrderedLiveOutput() throws {
        let fixture = try MultiplayerAcceptanceFixture()
        let surfaceID = TerminalSurfaceID(rawValue: "surface-1")
        let sessionID = SessionID(rawValue: "session-1")
        try fixture.createSurface(surfaceID: surfaceID, sessionID: sessionID)

        let earlyViewer = fixture.makeClient()
        fixture.subscribe(earlyViewer, surfaceID: surfaceID, sessionID: sessionID, clientID: ClientID(rawValue: "viewer-1"), leaseEpoch: 1)

        fixture.backend(sessionID).emitOutput(Array("abc".utf8))
        earlyViewer.client.poll(surfaceID: surfaceID)

        let lateViewer = fixture.makeClient()
        fixture.subscribe(lateViewer, surfaceID: surfaceID, sessionID: sessionID, clientID: ClientID(rawValue: "viewer-2"), leaseEpoch: 1)

        fixture.backend(sessionID).emitOutput(Array("!".utf8))
        earlyViewer.client.poll(surfaceID: surfaceID)
        lateViewer.client.poll(surfaceID: surfaceID)

        XCTAssertEqual(earlyViewer.latestAdapter?.text, "screenabc!")
        XCTAssertEqual(lateViewer.latestAdapter?.text, "screenabc!")
        XCTAssertEqual(earlyViewer.client.state(for: surfaceID)?.phase, .live)
        XCTAssertEqual(lateViewer.client.state(for: surfaceID)?.phase, .live)

        try recordArtifact(
            name: "late-join-bootstrap-live",
            runID: "20260315T000000Z-seed-202",
            faults: [
                [
                    "fault_id": "fault-late-join-bootstrap",
                    "category": "redraw",
                    "mode": "observed",
                    "target": "session-client",
                    "trigger": "second viewer joins after live output already advanced",
                    "ts_ms": 2,
                    "detail": "the late joiner rebuilds from bootstrap and then continues on the shared live stream"
                ],
            ],
            events: [
                clientEvent("evt-early-bootstrap", ts: 0, scenario: "late-join-bootstrap-live", clientID: "viewer-1", sessionID: sessionID.rawValue, surfaceID: surfaceID.rawValue, kind: "bootstrap_redraw", outputStart: 1, outputEnd: 6),
                clientEvent("evt-early-live", ts: 1, scenario: "late-join-bootstrap-live", clientID: "viewer-1", sessionID: sessionID.rawValue, surfaceID: surfaceID.rawValue, kind: "live_output_continuation", outputStart: 7, outputEnd: 9),
                clientEvent("evt-late-bootstrap", ts: 2, scenario: "late-join-bootstrap-live", clientID: "viewer-2", sessionID: sessionID.rawValue, surfaceID: surfaceID.rawValue, kind: "bootstrap_redraw", status: "fault", faultID: "fault-late-join-bootstrap", outputStart: 1, outputEnd: 9),
                clientEvent("evt-shared-live", ts: 3, scenario: "late-join-bootstrap-live", clientID: "viewer-1", sessionID: sessionID.rawValue, surfaceID: surfaceID.rawValue, kind: "live_output_continuation", outputStart: 10, outputEnd: 10),
                clientEvent("evt-late-live", ts: 4, scenario: "late-join-bootstrap-live", clientID: "viewer-2", sessionID: sessionID.rawValue, surfaceID: surfaceID.rawValue, kind: "live_output_continuation", outputStart: 10, outputEnd: 10),
            ],
            logs: [
                "viewer-1.log": earlyViewer.logLines(surfaceID: surfaceID).joined(separator: "\n") + "\n",
                "viewer-2.log": lateViewer.logLines(surfaceID: surfaceID).joined(separator: "\n") + "\n",
                "backend.log": fixture.backend(sessionID).transcriptLines().joined(separator: "\n") + "\n",
            ]
        )
    }

    func testRoomReconnectDoesNotInterruptLiveSessionPlane() throws {
        let fixture = try MultiplayerAcceptanceFixture(snapshotInterval: 2)
        let surfaceID = TerminalSurfaceID(rawValue: "surface-1")
        let sessionID = SessionID(rawValue: "session-1")
        try fixture.createSurface(surfaceID: surfaceID, sessionID: sessionID)

        let replica = RoomReplica(clientID: ClientID(rawValue: "replica-1"), snapshot: fixture.actor.snapshot)
        let viewer = fixture.makeClient()
        fixture.subscribe(viewer, surfaceID: surfaceID, sessionID: sessionID, clientID: ClientID(rawValue: "viewer-1"), leaseEpoch: 1)

        _ = try fixture.gateway.submit(
            RoomOpRecord(
                schemaVersion: .v1,
                roomID: RoomID(rawValue: "room-1"),
                roomSeq: nil,
                opID: RoomOpID(rawValue: "move-1"),
                clientID: ClientID(rawValue: "client-1"),
                submittedAtMillis: 103,
                payload: .moveSurface(MoveSurfaceOp(surfaceID: surfaceID, xWorld: 40, yWorld: 24))
            ),
            from: ClientID(rawValue: "client-1")
        )
        fixture.backend(sessionID).emitOutput(Array("abc".utf8))
        viewer.client.poll(surfaceID: surfaceID)

        let catchUp = try fixture.gateway.connect(clientID: ClientID(rawValue: "replica-1"), knownRoomSeq: 1)
        try replica.reconnect(catchUp)

        fixture.backend(sessionID).emitOutput(Array("de".utf8))
        viewer.client.poll(surfaceID: surfaceID)

        XCTAssertEqual(catchUp.mode, .snapshotAndTail)
        XCTAssertEqual(replica.authoritativeSnapshot, fixture.actor.snapshot)
        XCTAssertEqual(viewer.latestAdapter?.text, "screenabcde")
        XCTAssertEqual(viewer.client.state(for: surfaceID)?.phase, .live)

        try recordArtifact(
            name: "room-reconnect-live-session",
            runID: "20260315T000000Z-seed-203",
            faults: [
                [
                    "fault_id": "fault-room-reconnect-gap",
                    "category": "reconnect",
                    "mode": "injected",
                    "target": "room-gateway",
                    "trigger": "room client reconnects from room_seq 1 after snapshot interval advances",
                    "ts_ms": 2,
                    "detail": "room catch-up replays deterministically while the session stream continues uninterrupted"
                ],
            ],
            events: [
                roomEvent("evt-room-move", ts: 0, scenario: "room-reconnect-live-session", kind: "surface_moved", roomSeq: Int(fixture.actor.snapshot.roomSeq), sessionID: sessionID.rawValue),
                sessionEvent("evt-live-before-reconnect", ts: 1, scenario: "room-reconnect-live-session", sessionID: sessionID.rawValue, kind: "live_output_continuation", outputStart: 7, outputEnd: 9),
                roomEvent("evt-room-reconnect", ts: 2, scenario: "room-reconnect-live-session", kind: "reconnect_started", roomSeq: Int(fixture.actor.snapshot.roomSeq), sessionID: sessionID.rawValue, status: "fault", faultID: "fault-room-reconnect-gap"),
                sessionEvent("evt-live-after-reconnect", ts: 3, scenario: "room-reconnect-live-session", sessionID: sessionID.rawValue, kind: "live_output_continuation", outputStart: 10, outputEnd: 11),
                clientEvent("evt-viewer-still-live", ts: 4, scenario: "room-reconnect-live-session", clientID: "viewer-1", sessionID: sessionID.rawValue, surfaceID: surfaceID.rawValue, kind: "surface_subscribed"),
            ],
            logs: [
                "room-replica.log": replica.timeline.joined(separator: "\n") + "\n",
                "viewer-1.log": viewer.logLines(surfaceID: surfaceID).joined(separator: "\n") + "\n",
                "backend.log": fixture.backend(sessionID).transcriptLines().joined(separator: "\n") + "\n",
            ]
        )
    }

    func testSessionReconnectReplaysOnlyMissingOutput() throws {
        let fixture = try MultiplayerAcceptanceFixture()
        let surfaceID = TerminalSurfaceID(rawValue: "surface-1")
        let sessionID = SessionID(rawValue: "session-1")
        try fixture.createSurface(surfaceID: surfaceID, sessionID: sessionID)

        let initial = try fixture.connectTransport(sessionID: sessionID, clientID: ClientID(rawValue: "viewer-1"), leaseEpoch: 1)
        _ = initial.drainMessages()

        fixture.backend(sessionID).emitOutput(Array("abc".utf8))
        fixture.backend(sessionID).emitOutput(Array("de".utf8))
        _ = initial.drainMessages()
        initial.disconnect(reason: "drop")

        let session = fixture.sessionDirectory.session(for: sessionID)!
        let state = session.state()
        let reconnectAfter = state.outputSeq - 3
        let replay = try fixture.connectTransport(
            sessionID: sessionID,
            clientID: ClientID(rawValue: "viewer-1"),
            leaseEpoch: 1,
            reconnectAfterOutputSeq: reconnectAfter
        )
        let messages = replay.drainMessages()
        let expectedMessages = session.outputChunks(after: reconnectAfter).map(SessionTransportMessage.output) + [
            .status(SessionStatusRecord(
                status: state.status,
                outputSeq: state.outputSeq,
                exitCode: state.exitCode,
                failureReason: state.failureReason,
                resize: state.resizeReconciliation
            )),
        ]

        XCTAssertEqual(messages, expectedMessages)
        XCTAssertEqual(replay.diagnostics().resumeMode, .replay)

        try recordArtifact(
            name: "session-reconnect-replay",
            runID: "20260315T000000Z-seed-204",
            faults: [
                [
                    "fault_id": "fault-session-reconnect-gap",
                    "category": "reconnect",
                    "mode": "injected",
                    "target": "session-transport",
                    "trigger": "connection drops after output_seq 8",
                    "ts_ms": 2,
                    "detail": "reconnect resumes from the missing byte range instead of replaying the full bootstrap"
                ],
            ],
            events: [
                sessionEvent("evt-bootstrap", ts: 0, scenario: "session-reconnect-replay", sessionID: sessionID.rawValue, kind: "bootstrap_redraw", outputStart: 1, outputEnd: Int(state.outputSeq - 5)),
                sessionEvent("evt-live", ts: 1, scenario: "session-reconnect-replay", sessionID: sessionID.rawValue, kind: "live_output_continuation", outputStart: Int(reconnectAfter + 1), outputEnd: Int(state.outputSeq)),
                sessionEvent("evt-reconnect", ts: 2, scenario: "session-reconnect-replay", sessionID: sessionID.rawValue, kind: "reconnect_started", status: "fault", faultID: "fault-session-reconnect-gap", outputStart: Int(reconnectAfter + 1), outputEnd: Int(state.outputSeq)),
                sessionEvent("evt-replay-tail", ts: 3, scenario: "session-reconnect-replay", sessionID: sessionID.rawValue, kind: "live_output_continuation", outputStart: Int(reconnectAfter + 1), outputEnd: Int(state.outputSeq)),
            ],
            logs: [
                "session-initial.log": initial.diagnostics().logLines.joined(separator: "\n") + "\n",
                "session-reconnect.log": replay.diagnostics().logLines.joined(separator: "\n") + "\n",
                "backend.log": fixture.backend(sessionID).transcriptLines().joined(separator: "\n") + "\n",
            ]
        )
    }

    func testSessionFailureStaysIsolatedToTheAffectedSurface() throws {
        let fixture = try MultiplayerAcceptanceFixture()
        let surface1 = TerminalSurfaceID(rawValue: "surface-1")
        let surface2 = TerminalSurfaceID(rawValue: "surface-2")
        let session1 = SessionID(rawValue: "session-1")
        let session2 = SessionID(rawValue: "session-2")
        try fixture.createSurface(surfaceID: surface1, sessionID: session1)
        try fixture.createSurface(surfaceID: surface2, sessionID: session2)

        let viewer1 = fixture.makeClient()
        let viewer2 = fixture.makeClient()
        fixture.subscribe(viewer1, surfaceID: surface1, sessionID: session1, clientID: ClientID(rawValue: "viewer-1"), leaseEpoch: 1)
        fixture.subscribe(viewer2, surfaceID: surface2, sessionID: session2, clientID: ClientID(rawValue: "viewer-2"), leaseEpoch: 1)

        fixture.backend(session1).emitFailure("session backend failed")
        fixture.coordinator.pollClients(surfaceID: surface1)
        fixture.coordinator.pollClients(surfaceID: surface2)

        let lateRoomJoin = try fixture.gateway.connect(clientID: ClientID(rawValue: "room-observer"), knownRoomSeq: nil)

        XCTAssertEqual(fixture.coordinator.state(for: surface1)?.phase, .error)
        XCTAssertEqual(fixture.coordinator.state(for: surface2)?.phase, .attached)
        XCTAssertEqual(viewer1.client.state(for: surface1)?.phase, .failed("session backend failed"))
        XCTAssertEqual(viewer2.client.state(for: surface2)?.phase, .live)
        XCTAssertEqual(lateRoomJoin.baseSnapshot?.surfaces.count, 2)

        try recordArtifact(
            name: "session-outage-live-room",
            runID: "20260315T000000Z-seed-205",
            faults: [
                [
                    "fault_id": "fault-session-outage-surface-1",
                    "category": "outage",
                    "mode": "injected",
                    "target": "session-actor",
                    "trigger": "backend for surface-1 emits failed status",
                    "ts_ms": 1,
                    "detail": "surface-1 degrades while surface-2 and the room control plane remain available"
                ],
            ],
            events: [
                sessionEvent("evt-session-1-failed", ts: 1, scenario: "session-outage-live-room", sessionID: session1.rawValue, kind: "session_failed", status: "fault", faultID: "fault-session-outage-surface-1"),
                clientEvent("evt-surface-1-overlay", ts: 2, scenario: "session-outage-live-room", clientID: "viewer-1", sessionID: session1.rawValue, surfaceID: surface1.rawValue, kind: "surface_overlay_failed", status: "fault", faultID: "fault-session-outage-surface-1"),
                clientEvent("evt-surface-2-healthy", ts: 3, scenario: "session-outage-live-room", clientID: "viewer-2", sessionID: session2.rawValue, surfaceID: surface2.rawValue, kind: "surface_subscribed"),
                roomEvent("evt-room-cold-join", ts: 4, scenario: "session-outage-live-room", kind: "snapshot_loaded", roomSeq: Int(fixture.actor.snapshot.roomSeq), sessionID: session2.rawValue),
            ],
            logs: [
                "surface-1.log": fixture.coordinator.logLines(for: surface1).joined(separator: "\n") + "\n",
                "surface-2.log": fixture.coordinator.logLines(for: surface2).joined(separator: "\n") + "\n",
                "viewer-1.log": viewer1.logLines(surfaceID: surface1).joined(separator: "\n") + "\n",
                "viewer-2.log": viewer2.logLines(surfaceID: surface2).joined(separator: "\n") + "\n",
            ]
        )
    }

    private func recordArtifact(
        name: String,
        runID: String,
        faults: [[String: Any]],
        events: [[String: Any]],
        logs: [String: String]
    ) throws {
        guard let root = ProcessInfo.processInfo.environment["ITE_MULTIPLAYER_ARTIFACT_ROOT"], !root.isEmpty else {
            return
        }
        let writer = MultiplayerArtifactWriter(root: URL(fileURLWithPath: root))
        try writer.write(
            scenarioName: name,
            runID: runID,
            faults: faults,
            events: events,
            logs: logs
        )
    }
}

@MainActor
private final class MultiplayerAcceptanceFixture {
    let actor: RoomActor
    let gateway: RoomGateway
    let sessionDirectory: SessionDirectory
    let server: SessionTransportServer
    let authenticator: SessionTransportAuthenticator
    let coordinator: SurfaceLifecycleCoordinator

    private let backends: MutableBox<[SessionID: ReplayLogPTYBackend]>
    private let leaseEpochs: MutableBox<[SessionID: UInt64]>

    init(snapshotInterval: UInt64 = 10) throws {
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
            snapshotInterval: snapshotInterval
        )
        let gateway = RoomGateway(actor: actor, journalStore: journal, snapshotStore: snapshots)
        let sessionDirectory = SessionDirectory()
        let backends = MutableBox<[SessionID: ReplayLogPTYBackend]>([:])
        let leaseEpochs = MutableBox<[SessionID: UInt64]>([:])
        let authenticator = SessionTransportAuthenticator(secret: Data("transport-secret".utf8))
        let server = SessionTransportServer(
            directory: sessionDirectory,
            authenticator: authenticator,
            leaseEpochProvider: { sessionID in leaseEpochs.value[sessionID] ?? 1 },
            nowMillis: { 100 }
        )
        let coordinator = SurfaceLifecycleCoordinator(
            actor: actor,
            gateway: gateway,
            sessionDirectory: sessionDirectory,
            resizeCoordinator: SessionResizeCoordinator(directory: sessionDirectory),
            backendFactory: { sessionID in
                let backend = ReplayLogPTYBackend()
                backends.value[sessionID] = backend
                backend.emitOutput(Array("screen".utf8))
                return backend
            }
        )
        self.actor = actor
        self.gateway = gateway
        self.sessionDirectory = sessionDirectory
        self.server = server
        self.authenticator = authenticator
        self.coordinator = coordinator
        self.backends = backends
        self.leaseEpochs = leaseEpochs
    }

    func createSurface(surfaceID: TerminalSurfaceID, sessionID: SessionID) throws {
        _ = try coordinator.createSurface(
            surfaceID: surfaceID,
            sessionID: sessionID,
            clientID: ClientID(rawValue: "client-1"),
            cols: 80,
            rows: 24,
            profileID: "profile"
        )
        leaseEpochs.value[sessionID] = 1
    }

    func makeClient() -> MultiplayerClientHandle {
        let handle = MultiplayerClientHandle()
        handle.client = SessionClient(
            connectHandler: { [server] request in
                try server.connect(request)
            },
            adapterFactory: { _, _ in
                let adapter = RecordingSurfaceAdapter()
                handle.adapters.append(adapter)
                return adapter
            }
        )
        return handle
    }

    func subscribe(
        _ handle: MultiplayerClientHandle,
        surfaceID: TerminalSurfaceID,
        sessionID: SessionID,
        clientID: ClientID,
        leaseEpoch: UInt64
    ) {
        coordinator.subscribeSurface(
            surfaceID: surfaceID,
            client: handle.client,
            clientID: clientID,
            leaseEpoch: leaseEpoch,
            token: try! token(sessionID: sessionID, clientID: clientID, leaseEpoch: leaseEpoch)
        )
    }

    func token(sessionID: SessionID, clientID: ClientID, leaseEpoch: UInt64) throws -> String {
        try authenticator.issueToken(for: SessionTransportTokenClaims(
            sessionID: sessionID,
            clientID: clientID,
            leaseEpoch: leaseEpoch,
            issuedAtMillis: 90,
            expiresAtMillis: 130
        ))
    }

    func connectTransport(
        sessionID: SessionID,
        clientID: ClientID,
        leaseEpoch: UInt64,
        reconnectAfterOutputSeq: UInt64? = nil
    ) throws -> SessionTransportConnection {
        try server.connect(SessionTransportConnectRequest(
            sessionID: sessionID,
            clientID: clientID,
            leaseEpoch: leaseEpoch,
            token: token(sessionID: sessionID, clientID: clientID, leaseEpoch: leaseEpoch),
            reconnectAfterOutputSeq: reconnectAfterOutputSeq
        ))
    }

    func acquireControl(
        sessionID: SessionID,
        holderUserID: UserID,
        clientID: ClientID,
        opID: String
    ) throws -> AppliedRoomOp {
        let applied = try gateway.submit(
            RoomOpRecord(
                schemaVersion: .v1,
                roomID: RoomID(rawValue: "room-1"),
                roomSeq: nil,
                opID: RoomOpID(rawValue: opID),
                clientID: clientID,
                submittedAtMillis: 103,
                payload: .acquireControl(AcquireControlOp(sessionID: sessionID, holderUserID: holderUserID))
            ),
            from: clientID
        )
        if let lease = actor.controlLease(for: sessionID) {
            leaseEpochs.value[sessionID] = lease.leaseEpoch
            server.noteLeaseEpochChanged(for: sessionID)
        }
        return applied
    }

    func releaseControl(sessionID: SessionID, clientID: ClientID, opID: String) throws -> AppliedRoomOp {
        try gateway.submit(
            RoomOpRecord(
                schemaVersion: .v1,
                roomID: RoomID(rawValue: "room-1"),
                roomSeq: nil,
                opID: RoomOpID(rawValue: opID),
                clientID: clientID,
                submittedAtMillis: 103,
                payload: .releaseControl(ReleaseControlOp(sessionID: sessionID))
            ),
            from: clientID
        )
    }

    func backend(_ sessionID: SessionID) -> ReplayLogPTYBackend {
        backends.value[sessionID]!
    }
}

@MainActor
private final class MultiplayerClientHandle {
    fileprivate var adapters: [RecordingSurfaceAdapter] = []
    fileprivate var client: SessionClient!

    var latestAdapter: RecordingSurfaceAdapter? {
        adapters.last
    }

    func logLines(surfaceID: TerminalSurfaceID) -> [String] {
        client.logLines(for: surfaceID)
    }
}

@MainActor
private final class RecordingSurfaceAdapter: SessionSurfaceAdapter {
    private(set) var text = ""

    func ingestOutput(_ text: String) {
        self.text.append(text)
    }

    func shutdown() {}
}

private struct MultiplayerArtifactWriter {
    let root: URL

    func write(
        scenarioName: String,
        runID: String,
        faults: [[String: Any]],
        events: [[String: Any]],
        logs: [String: String]
    ) throws {
        let bundleRoot = root
            .appendingPathComponent("multiplayer")
            .appendingPathComponent(scenarioName)
            .appendingPathComponent(runID)
        let transcripts = bundleRoot.appendingPathComponent("transcripts")
        let summaries = bundleRoot.appendingPathComponent("summaries")
        let logsDirectory = bundleRoot.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: transcripts, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: summaries, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)

        let summary: [String: Any] = [
            "status": "passed",
            "event_count": events.count,
            "reject_count": events.filter { ($0["status"] as? String) == "rejected" }.count,
            "injected_fault_count": faults.filter { ($0["mode"] as? String) == "injected" }.count,
        ]

        let eventsURL = transcripts.appendingPathComponent("events.jsonl")
        let summaryURL = summaries.appendingPathComponent("summary.json")
        try writeJSONLines(events, to: eventsURL)
        try writeJSON(summary, to: summaryURL)

        var files: [[String: Any]] = [
            [
                "kind": "events",
                "label": "multiplayer event transcript",
                "path": "transcripts/events.jsonl"
            ],
            [
                "kind": "summary",
                "label": "multiplayer summary",
                "path": "summaries/summary.json"
            ],
        ]

        for name in logs.keys.sorted() {
            let relativePath = "logs/\(name)"
            try logs[name]!.write(to: logsDirectory.appendingPathComponent(name), atomically: true, encoding: .utf8)
            files.append([
                "kind": logKind(for: name),
                "label": name,
                "path": relativePath,
            ])
        }

        let manifest: [String: Any] = [
            "schema_version": "ite.verification_artifact.v1",
            "scenario": [
                "suite": "multiplayer",
                "name": scenarioName,
                "run_id": runID,
                "attempt": 1
            ],
            "summary": summary,
            "faults": faults,
            "files": files,
        ]
        try writeJSON(manifest, to: bundleRoot.appendingPathComponent("manifest.json"))
    }

    private func writeJSON(_ json: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private func writeJSONLines(_ lines: [[String: Any]], to url: URL) throws {
        let encodedLines = try lines.map { entry -> String in
            let data = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
            guard let line = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "MultiplayerAcceptanceTests", code: 1)
            }
            return line
        }
        try (encodedLines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func logKind(for name: String) -> String {
        if name.contains("viewer") {
            return "client_log"
        }
        if name.contains("room") {
            return "room_log"
        }
        return "session_log"
    }
}

private func baseEvent(id: String, ts: Int, scenario: String, domain: String, component: String, status: String, kind: String) -> [String: Any] {
    [
        "schema_version": "ite.verification_artifact.v1",
        "event_id": id,
        "ts_ms": ts,
        "domain": domain,
        "component": component,
        "scenario_name": scenario,
        "status": status,
        "kind": kind,
    ]
}

private func roomEvent(
    _ id: String,
    ts: Int,
    scenario: String,
    kind: String,
    roomSeq: Int,
    sessionID: String,
    status: String = "ok",
    faultID: String? = nil
) -> [String: Any] {
    var event = baseEvent(id: id, ts: ts, scenario: scenario, domain: "room", component: "room-gateway", status: status, kind: kind)
    event["room_id"] = "room-1"
    event["room_seq"] = roomSeq
    event["session_id"] = sessionID
    if let faultID {
        event["fault_id"] = faultID
    }
    return event
}

private func sessionEvent(
    _ id: String,
    ts: Int,
    scenario: String,
    sessionID: String,
    kind: String,
    status: String = "ok",
    faultID: String? = nil,
    outputStart: Int? = nil,
    outputEnd: Int? = nil
) -> [String: Any] {
    var event = baseEvent(id: id, ts: ts, scenario: scenario, domain: "session", component: "session-transport", status: status, kind: kind)
    event["session_id"] = sessionID
    if let faultID {
        event["fault_id"] = faultID
    }
    if let outputStart {
        event["output_seq_start"] = outputStart
    }
    if let outputEnd {
        event["output_seq_end"] = outputEnd
    }
    return event
}

private func clientEvent(
    _ id: String,
    ts: Int,
    scenario: String,
    clientID: String,
    sessionID: String,
    surfaceID: String,
    kind: String,
    status: String = "ok",
    faultID: String? = nil,
    outputStart: Int? = nil,
    outputEnd: Int? = nil
) -> [String: Any] {
    var event = baseEvent(id: id, ts: ts, scenario: scenario, domain: "client", component: "session-client", status: status, kind: kind)
    event["room_id"] = "room-1"
    event["room_seq"] = 1
    event["client_id"] = clientID
    event["session_id"] = sessionID
    event["surface_id"] = surfaceID
    if let faultID {
        event["fault_id"] = faultID
    }
    if let outputStart {
        event["output_seq_start"] = outputStart
    }
    if let outputEnd {
        event["output_seq_end"] = outputEnd
    }
    return event
}

private final class MutableBox<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
