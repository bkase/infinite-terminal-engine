import Foundation
import XCTest

final class VerificationArtifactToolTests: XCTestCase {
    func testSmokeBundleValidates() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let result = try runTool(arguments: ["smoke", tempDirectory.path])
        XCTAssertTrue(result.stdout.contains("manifest.json"))
    }

    func testValidatorAcceptsRepresentativeCrossDomainBundle() throws {
        let bundleRoot = try makeBundle(
            manifest: [
                "schema_version": "ite.verification_artifact.v1",
                "scenario": [
                    "suite": "room",
                    "name": "cross-domain-contract",
                    "run_id": "20260315T120000Z-seed-11",
                    "seed": 11,
                    "attempt": 1,
                ],
                "summary": [
                    "status": "failed",
                    "event_count": 6,
                    "reject_count": 1,
                    "injected_fault_count": 1,
                ],
                "faults": [
                    [
                        "fault_id": "fault-reconnect",
                        "category": "reconnect",
                        "mode": "injected",
                        "target": "room-gateway",
                        "trigger": "drop tail",
                        "ts_ms": 10,
                        "detail": "simulate reconnect gap",
                    ],
                ],
                "files": [
                    [
                        "kind": "events",
                        "label": "event transcript",
                        "path": "transcripts/events.jsonl",
                    ],
                    [
                        "kind": "summary",
                        "label": "summary",
                        "path": "summaries/summary.json",
                    ],
                ],
            ],
            summary: [
                "status": "failed",
                "event_count": 6,
                "reject_count": 1,
                "injected_fault_count": 1,
            ],
            events: [
                [
                    "schema_version": "ite.verification_artifact.v1",
                    "event_id": "evt-room",
                    "ts_ms": 11,
                    "domain": "room",
                    "component": "room-actor",
                    "scenario_name": "cross-domain-contract",
                    "status": "ok",
                    "kind": "snapshot_loaded",
                    "room_id": "room-1",
                    "room_seq": 3,
                ],
                [
                    "schema_version": "ite.verification_artifact.v1",
                    "event_id": "evt-session",
                    "ts_ms": 12,
                    "domain": "session",
                    "component": "terminal-gateway",
                    "scenario_name": "cross-domain-contract",
                    "status": "ok",
                    "kind": "bootstrap_redraw",
                    "session_id": "session-1",
                ],
                [
                    "schema_version": "ite.verification_artifact.v1",
                    "event_id": "evt-client",
                    "ts_ms": 13,
                    "domain": "client",
                    "component": "room-client",
                    "scenario_name": "cross-domain-contract",
                    "status": "fault",
                    "kind": "reconnect_started",
                    "client_id": "client-1",
                    "fault_id": "fault-reconnect",
                ],
                [
                    "schema_version": "ite.verification_artifact.v1",
                    "event_id": "evt-ghostty",
                    "ts_ms": 14,
                    "domain": "ghostty",
                    "component": "ghostty-adapter",
                    "scenario_name": "cross-domain-contract",
                    "status": "ok",
                    "kind": "redraw_completed",
                    "surface_id": "surface-1",
                ],
                [
                    "schema_version": "ite.verification_artifact.v1",
                    "event_id": "evt-compositor",
                    "ts_ms": 15,
                    "domain": "compositor",
                    "component": "metal-compositor",
                    "scenario_name": "cross-domain-contract",
                    "status": "ok",
                    "kind": "frame_presented",
                    "surface_id": "surface-1",
                ],
                [
                    "schema_version": "ite.verification_artifact.v1",
                    "event_id": "evt-security",
                    "ts_ms": 16,
                    "domain": "security",
                    "component": "terminal-gateway",
                    "scenario_name": "cross-domain-contract",
                    "status": "rejected",
                    "kind": "input_denied",
                    "decision": "deny",
                    "reject_reason": "lease_epoch_mismatch",
                ],
            ]
        )
        defer { try? FileManager.default.removeItem(at: bundleRoot) }

        let result = try runTool(arguments: ["validate", bundleRoot.appendingPathComponent("manifest.json").path])
        XCTAssertTrue(result.stdout.contains("validated"))
    }

    func testValidatorRejectsSummaryMismatch() throws {
        let bundleRoot = try makeBundle(
            manifest: [
                "schema_version": "ite.verification_artifact.v1",
                "scenario": [
                    "suite": "room",
                    "name": "invalid-summary",
                    "run_id": "20260315T120001Z-seed-13",
                ],
                "summary": [
                    "status": "passed",
                    "event_count": 2,
                    "reject_count": 0,
                    "injected_fault_count": 0,
                ],
                "faults": [],
                "files": [
                    [
                        "kind": "events",
                        "label": "event transcript",
                        "path": "transcripts/events.jsonl",
                    ],
                    [
                        "kind": "summary",
                        "label": "summary",
                        "path": "summaries/summary.json",
                    ],
                ],
            ],
            summary: [
                "status": "passed",
                "event_count": 1,
                "reject_count": 0,
                "injected_fault_count": 0,
            ],
            events: [
                [
                    "schema_version": "ite.verification_artifact.v1",
                    "event_id": "evt-room",
                    "ts_ms": 11,
                    "domain": "room",
                    "component": "room-actor",
                    "scenario_name": "invalid-summary",
                    "status": "ok",
                    "kind": "snapshot_loaded",
                    "room_id": "room-1",
                    "room_seq": 3,
                ],
            ]
        )
        defer { try? FileManager.default.removeItem(at: bundleRoot) }

        let result = try runToolAllowingFailure(arguments: ["validate", bundleRoot.appendingPathComponent("manifest.json").path])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("summary file content must match manifest.summary"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func makeBundle(
        manifest: [String: Any],
        summary: [String: Any],
        events: [[String: Any]]
    ) throws -> URL {
        let root = try makeTemporaryDirectory()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("transcripts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("summaries"), withIntermediateDirectories: true)

        let encoder = JSONSerialization.self
        let manifestData = try encoder.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try manifestData.write(to: root.appendingPathComponent("manifest.json"))

        let summaryData = try encoder.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
        try summaryData.write(to: root.appendingPathComponent("summaries/summary.json"))

        let transcriptURL = root.appendingPathComponent("transcripts/events.jsonl")
        let transcript = try events
            .map { event in
                let data = try encoder.data(withJSONObject: event, options: [.sortedKeys])
                guard let line = String(data: data, encoding: .utf8) else {
                    throw NSError(domain: "VerificationArtifactToolTests", code: 1)
                }
                return line
            }
            .joined(separator: "\n") + "\n"
        try transcript.write(to: transcriptURL, atomically: true, encoding: .utf8)

        return root
    }

    private func runTool(arguments: [String]) throws -> CommandResult {
        let result = try runToolAllowingFailure(arguments: arguments)
        XCTAssertEqual(result.exitCode, 0, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
        return result
    }

    private func runToolAllowingFailure(arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [toolPath] + arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    private var toolPath: String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        return testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/verification-artifact-tool.py")
            .path
    }
}

private struct CommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}
