import Foundation
import XCTest

final class ReplayArtifactToolTests: XCTestCase {
    func testRoomReplayMatchesExpectedSnapshot() throws {
        let bundleRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: bundleRoot) }

        try writeJSON([
            "schema_version": "ite.verification_artifact.v1",
            "scenario": [
                "suite": "multiplayer",
                "name": "room-reconnect-live-session",
                "run_id": "20260315T000000Z-seed-203",
            ],
            "summary": [
                "status": "passed",
                "event_count": 1,
                "reject_count": 0,
                "injected_fault_count": 0,
            ],
            "faults": [],
            "files": [
                ["kind": "events", "label": "events", "path": "transcripts/events.jsonl"],
                ["kind": "summary", "label": "summary", "path": "summaries/summary.json"],
                ["kind": "room_snapshot", "label": "base snapshot", "path": "replay/room/base-snapshot.json"],
                ["kind": "room_journal", "label": "journal", "path": "replay/room/journal.json"],
                ["kind": "room_expected_snapshot", "label": "expected snapshot", "path": "replay/room/expected-snapshot.json"],
            ],
        ], to: bundleRoot.appendingPathComponent("manifest.json"))
        try writeJSON([
            "status": "passed",
            "event_count": 1,
            "reject_count": 0,
            "injected_fault_count": 0,
        ], to: bundleRoot.appendingPathComponent("summaries/summary.json"))
        try writeText("{\"schema_version\":\"ite.verification_artifact.v1\"}\n", to: bundleRoot.appendingPathComponent("transcripts/events.jsonl"))
        try writeJSON([
            "schemaVersion": 1,
            "roomID": "room-1",
            "roomSeq": 2,
            "renderProfileIDs": ["profile"],
            "surfaces": [[
                "id": "surface-1",
                "sessionID": "session-1",
                "xWorld": 0,
                "yWorld": 0,
                "cols": 80,
                "rows": 24,
                "stackRank": 0,
                "profileID": "profile",
                "title": NSNull(),
                "state": "attached",
                "createdBy": "client-generated",
                "createdAtMillis": 100,
            ]],
            "controlLeases": [],
        ], to: bundleRoot.appendingPathComponent("replay/room/base-snapshot.json"))
        try writeJSON([[
            "schemaVersion": 1,
            "roomID": ["rawValue": "room-1"],
            "roomSeq": 3,
            "opID": "move-1",
            "clientID": "client-1",
            "submittedAtMillis": 101,
            "payload": [
                "kind": "move_surface",
                "payload": [
                    "surfaceID": "surface-1",
                    "xWorld": 12.5,
                    "yWorld": 6.0,
                ],
            ],
        ]], to: bundleRoot.appendingPathComponent("replay/room/journal.json"))
        try writeJSON([
            "schemaVersion": 1,
            "roomID": "room-1",
            "roomSeq": 3,
            "renderProfileIDs": ["profile"],
            "surfaces": [[
                "id": "surface-1",
                "sessionID": "session-1",
                "xWorld": 12.5,
                "yWorld": 6.0,
                "cols": 80,
                "rows": 24,
                "stackRank": 0,
                "profileID": "profile",
                "title": NSNull(),
                "state": "attached",
                "createdBy": "client-generated",
                "createdAtMillis": 100,
            ]],
            "controlLeases": [],
        ], to: bundleRoot.appendingPathComponent("replay/room/expected-snapshot.json"))

        let result = try runTool(arguments: ["room", bundleRoot.appendingPathComponent("manifest.json").path, "--check"])
        XCTAssertTrue(result.stdout.contains("\"roomSeq\": 3"))
    }

    func testSessionReplayMatchesExpectedOutput() throws {
        let bundleRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: bundleRoot) }

        try writeJSON([
            "schema_version": "ite.verification_artifact.v1",
            "scenario": [
                "suite": "multiplayer",
                "name": "session-reconnect-replay",
                "run_id": "20260315T000000Z-seed-204",
            ],
            "summary": [
                "status": "passed",
                "event_count": 1,
                "reject_count": 0,
                "injected_fault_count": 0,
            ],
            "faults": [],
            "files": [
                ["kind": "events", "label": "events", "path": "transcripts/events.jsonl"],
                ["kind": "summary", "label": "summary", "path": "summaries/summary.json"],
                ["kind": "session_bootstrap", "label": "bootstrap", "path": "replay/session/bootstrap.json"],
                ["kind": "session_output", "label": "output", "path": "replay/session/output.json"],
                ["kind": "session_expected_output", "label": "expected", "path": "replay/session/expected-output.json"],
            ],
        ], to: bundleRoot.appendingPathComponent("manifest.json"))
        try writeJSON([
            "status": "passed",
            "event_count": 1,
            "reject_count": 0,
            "injected_fault_count": 0,
        ], to: bundleRoot.appendingPathComponent("summaries/summary.json"))
        try writeText("{\"schema_version\":\"ite.verification_artifact.v1\"}\n", to: bundleRoot.appendingPathComponent("transcripts/events.jsonl"))
        try writeJSON([
            "session_id": "session-1",
            "output_seq_start": 1,
            "output_seq_end": 6,
            "bytes_utf8": "screen",
            "bytes_base64": Data("screen".utf8).base64EncodedString(),
        ], to: bundleRoot.appendingPathComponent("replay/session/bootstrap.json"))
        try writeJSON([
            [
                "seq_start": 7,
                "seq_end": 9,
                "bytes_utf8": "abc",
                "bytes_base64": Data("abc".utf8).base64EncodedString(),
            ],
            [
                "seq_start": 10,
                "seq_end": 11,
                "bytes_utf8": "de",
                "bytes_base64": Data("de".utf8).base64EncodedString(),
            ],
        ], to: bundleRoot.appendingPathComponent("replay/session/output.json"))
        try writeJSON([
            "session_id": "session-1",
            "bytes_utf8": "screenabcde",
            "bytes_base64": Data("screenabcde".utf8).base64EncodedString(),
        ], to: bundleRoot.appendingPathComponent("replay/session/expected-output.json"))

        let result = try runTool(arguments: ["session", bundleRoot.appendingPathComponent("manifest.json").path, "--check"])
        XCTAssertTrue(result.stdout.contains("screenabcde"))
    }

    func testSessionReplayReportsSequenceGap() throws {
        let bundleRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: bundleRoot) }

        try writeJSON([
            "schema_version": "ite.verification_artifact.v1",
            "scenario": [
                "suite": "multiplayer",
                "name": "session-gap",
                "run_id": "20260315T000000Z-seed-205",
            ],
            "summary": [
                "status": "passed",
                "event_count": 1,
                "reject_count": 0,
                "injected_fault_count": 0,
            ],
            "faults": [],
            "files": [
                ["kind": "events", "label": "events", "path": "transcripts/events.jsonl"],
                ["kind": "summary", "label": "summary", "path": "summaries/summary.json"],
                ["kind": "session_bootstrap", "label": "bootstrap", "path": "replay/session/bootstrap.json"],
                ["kind": "session_output", "label": "output", "path": "replay/session/output.json"],
            ],
        ], to: bundleRoot.appendingPathComponent("manifest.json"))
        try writeJSON([
            "status": "passed",
            "event_count": 1,
            "reject_count": 0,
            "injected_fault_count": 0,
        ], to: bundleRoot.appendingPathComponent("summaries/summary.json"))
        try writeText("{\"schema_version\":\"ite.verification_artifact.v1\"}\n", to: bundleRoot.appendingPathComponent("transcripts/events.jsonl"))
        try writeJSON([
            "session_id": "session-1",
            "output_seq_start": 1,
            "output_seq_end": 6,
            "bytes_utf8": "screen",
            "bytes_base64": Data("screen".utf8).base64EncodedString(),
        ], to: bundleRoot.appendingPathComponent("replay/session/bootstrap.json"))
        try writeJSON([[
            "seq_start": 8,
            "seq_end": 9,
            "bytes_utf8": "ab",
            "bytes_base64": Data("ab".utf8).base64EncodedString(),
        ]], to: bundleRoot.appendingPathComponent("replay/session/output.json"))

        let result = try runToolAllowingFailure(arguments: ["session", bundleRoot.appendingPathComponent("manifest.json").path])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("expected seq_start 7"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeJSON(_ object: Any, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private func writeText(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func runTool(arguments: [String]) throws -> ReplayCommandResult {
        let result = try runToolAllowingFailure(arguments: arguments)
        XCTAssertEqual(result.exitCode, 0, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
        return result
    }

    private func runToolAllowingFailure(arguments: [String]) throws -> ReplayCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [toolPath] + arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return ReplayCommandResult(
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
            .appendingPathComponent("scripts/replay-artifact-tool.py")
            .path
    }
}

private struct ReplayCommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}
