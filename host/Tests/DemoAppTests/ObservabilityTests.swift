import Foundation
import XCTest
@testable import DemoApp

@MainActor
final class ObservabilityTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Observability.nowMillis = { 1_710_460_800_000 }
    }

    override func tearDown() {
        Observability.sink = nil
        super.tearDown()
    }

    func testRepresentativeRoomSessionGhosttyAndCompositorFlowsEmitCorrelatableRecords() throws {
        let recorder = ObservabilityRecorder()
        Observability.sink = recorder

        let fixture = try makeFixture()
        _ = try fixture.gateway.connect(clientID: ClientID(rawValue: "client-1"), knownRoomSeq: nil)
        _ = try fixture.gateway.submit(record(opID: "op-1", payload: .createSurface(CreateSurfaceOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            xWorld: 0,
            yWorld: 0,
            cols: 80,
            rows: 24,
            profileID: "profile",
            terminalTemplate: nil
        ))), from: ClientID(rawValue: "client-1"))
        _ = try fixture.gateway.submit(record(opID: "op-2", payload: .attachSession(AttachSessionOp(
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            sessionID: SessionID(rawValue: "session-1")
        ))), from: ClientID(rawValue: "client-1"))

        let connection = try fixture.server.connect(SessionTransportConnectRequest(
            sessionID: SessionID(rawValue: "session-1"),
            clientID: ClientID(rawValue: "client-1"),
            leaseEpoch: 1,
            token: try fixture.authenticator.issueToken(for: SessionTransportTokenClaims(
                sessionID: SessionID(rawValue: "session-1"),
                clientID: ClientID(rawValue: "client-1"),
                leaseEpoch: 1,
                issuedAtMillis: 90,
                expiresAtMillis: 130
            )),
            reconnectAfterOutputSeq: nil
        ))
        _ = connection.drainMessages()
        try connection.sendInput(SessionTransportInputFrame(clientInputSeq: 1, bytes: Array("ls\n".utf8)))

        GhosttyObservability.recordPasteAudit(surfaceID: "surface-1", textByteCount: 6, bracketed: true)
        GhosttyObservability.recordResize(surfaceID: "surface-1", width: 1280, height: 800, backingScale: 2)
        GhosttyObservability.recordTexturePublishRequest(surfaceID: "surface-1", generation: 4)

        let profile = try RenderProfileCatalog.defaultProfile()
        var camera = CanvasCamera()
        camera.resize(width: 1600, height: 1200)
        let compositorMetrics = CompositorStressHarness.measureVisibility(
            surfaces: CompositorStressHarness.makeMixedSizeSurfaces(profileID: profile.id, count: 10),
            profilesByID: [profile.id: profile],
            camera: camera,
            backingScale: 2,
            iterations: 4
        )
        for metric in compositorMetrics.observabilityMetrics(correlationID: "corr-1") {
            recorder.record(metric: metric)
        }

        XCTAssertTrue(recorder.metrics.contains(where: { $0.name == "room.connect_total" }))
        XCTAssertTrue(recorder.metrics.contains(where: { $0.name == "room.apply_total" }))
        XCTAssertTrue(recorder.metrics.contains(where: { $0.name == "session.transport_connect_total" }))
        XCTAssertTrue(recorder.metrics.contains(where: { $0.name == "session.input_bytes" }))
        XCTAssertTrue(recorder.metrics.contains(where: { $0.name == "ghostty.paste_bytes" }))
        XCTAssertTrue(recorder.metrics.contains(where: { $0.name == "compositor.texture_memory_bytes" }))

        let roomLog = try XCTUnwrap(recorder.logs.last(where: { $0.event == "op_applied" }))
        XCTAssertEqual(roomLog.fields["room_id"], "room-1")
        XCTAssertEqual(roomLog.fields["client_id"], "client-1")
        XCTAssertEqual(roomLog.fields["op_id"], "op-2")

        let sessionLog = try XCTUnwrap(recorder.logs.first(where: { $0.event == "transport_connected" }))
        XCTAssertEqual(sessionLog.fields["session_id"], "session-1")
        XCTAssertEqual(sessionLog.fields["connection_id"], "session-session-1-conn-1")

        let ghosttyLog = try XCTUnwrap(recorder.logs.first(where: { $0.event == "paste_routed" }))
        XCTAssertEqual(ghosttyLog.fields["surface_id"], "surface-1")
        XCTAssertEqual(ghosttyLog.fields["bracketed"], "true")

        try recordArtifact(recorder: recorder)
    }

    private func recordArtifact(recorder: ObservabilityRecorder) throws {
        guard let root = ProcessInfo.processInfo.environment["ITE_OBSERVABILITY_ARTIFACT_ROOT"], !root.isEmpty else {
            return
        }

        let writer = ObservabilityArtifactWriter(root: URL(fileURLWithPath: root))
        try writer.write(recorder: recorder)
    }

    private func makeFixture() throws -> (gateway: RoomGateway, server: SessionTransportServer, authenticator: SessionTransportAuthenticator) {
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
        let directory = SessionDirectory()
        let backend = ReplayLogPTYBackend()
        let session = try directory.provision(
            sessionID: SessionID(rawValue: "session-1"),
            roomID: RoomID(rawValue: "room-1"),
            surfaceID: TerminalSurfaceID(rawValue: "surface-1"),
            initialSize: TerminalSessionSize(cols: 80, rows: 24)
        ) {
            backend
        }
        try session.start()
        backend.emitOutput(Array("screen".utf8))
        let authenticator = SessionTransportAuthenticator(secret: Data("transport-secret".utf8))
        let server = SessionTransportServer(
            directory: directory,
            authenticator: authenticator,
            leaseEpochProvider: { _ in 1 },
            nowMillis: { 100 }
        )
        return (gateway, server, authenticator)
    }

    private func record(opID: String, payload: RoomOperationPayload) -> RoomOpRecord {
        RoomOpRecord(
            schemaVersion: .v1,
            roomID: RoomID(rawValue: "room-1"),
            roomSeq: nil,
            opID: RoomOpID(rawValue: opID),
            clientID: ClientID(rawValue: "client-1"),
            submittedAtMillis: 100,
            payload: payload
        )
    }
}

private struct ObservabilityArtifactWriter {
    let root: URL

    func write(recorder: ObservabilityRecorder) throws {
        let scenarioName = "observability-smoke"
        let runID = "20260315T000000Z-seed-301"
        let bundleRoot = root
            .appendingPathComponent("observability")
            .appendingPathComponent(scenarioName)
            .appendingPathComponent(runID)
        let transcripts = bundleRoot.appendingPathComponent("transcripts")
        let summaries = bundleRoot.appendingPathComponent("summaries")
        let logsDirectory = bundleRoot.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: transcripts, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: summaries, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)

        var events: [[String: Any]] = []
        for (index, log) in recorder.logs.enumerated() {
            let domain: String
            switch log.domain {
            case "ghostty":
                domain = "ghostty"
            case "room":
                domain = "room"
            default:
                domain = "session"
            }

            var event: [String: Any] = [
                "schema_version": "ite.verification_artifact.v1",
                "event_id": "evt-observability-\(index)",
                "ts_ms": Int(log.tsMillis),
                "domain": domain,
                "component": log.component,
                "scenario_name": scenarioName,
                "status": log.level == "error" ? "fault" : "ok",
                "kind": log.event,
                "room_id": log.fields["room_id"] ?? "room-1",
                "room_seq": Int(log.fields["room_seq"] ?? "0") ?? 0,
                "session_id": log.fields["session_id"] ?? "session-1",
                "client_id": log.fields["client_id"] ?? "client-1",
                "surface_id": log.fields["surface_id"] ?? "surface-1",
            ]
            if domain == "ghostty" {
                event.removeValue(forKey: "room_id")
                event.removeValue(forKey: "room_seq")
                event.removeValue(forKey: "session_id")
                event.removeValue(forKey: "client_id")
            }
            events.append(event)
        }
        let summary: [String: Any] = [
            "status": "passed",
            "event_count": events.count,
            "reject_count": 0,
            "injected_fault_count": 0,
        ]
        let metricsPayload = try JSONEncoder().encode(recorder.metrics)
        try metricsPayload.write(to: logsDirectory.appendingPathComponent("metrics.json"))
        let logsPayload = try JSONEncoder().encode(recorder.logs)
        try logsPayload.write(to: logsDirectory.appendingPathComponent("logs.json"))
        try writeJSONLines(events, to: transcripts.appendingPathComponent("events.jsonl"))
        try writeJSON(summary, to: summaries.appendingPathComponent("summary.json"))
        try writeJSON([
            "schema_version": "ite.verification_artifact.v1",
            "scenario": [
                "suite": "observability",
                "name": scenarioName,
                "run_id": runID,
                "attempt": 1,
            ],
            "summary": summary,
            "faults": [],
            "files": [
                ["kind": "events", "label": "observability events", "path": "transcripts/events.jsonl"],
                ["kind": "summary", "label": "observability summary", "path": "summaries/summary.json"],
                ["kind": "metrics", "label": "metrics payload", "path": "logs/metrics.json"],
                ["kind": "logs", "label": "structured logs payload", "path": "logs/logs.json"],
            ],
        ], to: bundleRoot.appendingPathComponent("manifest.json"))
    }

    private func writeJSON(_ json: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private func writeJSONLines(_ lines: [[String: Any]], to url: URL) throws {
        let encodedLines = try lines.map { line -> String in
            let data = try JSONSerialization.data(withJSONObject: line, options: [.sortedKeys])
            return String(decoding: data, as: UTF8.self)
        }
        try (encodedLines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
