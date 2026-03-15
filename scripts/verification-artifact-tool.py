#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path


SCHEMA_VERSION = "ite.verification_artifact.v1"
ALLOWED_DOMAINS = {
    "room",
    "session",
    "client",
    "ghostty",
    "compositor",
    "security",
}
ALLOWED_SUMMARY_STATUS = {"passed", "failed"}
ALLOWED_EVENT_STATUS = {"ok", "rejected", "fault"}
ALLOWED_FAULT_CATEGORIES = {
    "reconnect",
    "lease",
    "outage",
    "redraw",
    "security_denial",
}
ALLOWED_FAULT_MODES = {"injected", "observed"}
REQUIRED_FILE_KINDS = {"events", "summary"}


class ValidationError(Exception):
    pass


def _read_json(path: Path):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError as exc:
        raise ValidationError(f"missing file: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ValidationError(f"invalid JSON in {path}: {exc}") from exc


def _require(condition: bool, message: str):
    if not condition:
        raise ValidationError(message)


def _require_non_empty_string(value, field: str):
    _require(isinstance(value, str) and value.strip(), f"{field} must be a non-empty string")


def _validate_relative_path(path_value: str, field: str):
    _require_non_empty_string(path_value, field)
    candidate = Path(path_value)
    _require(not candidate.is_absolute(), f"{field} must be relative: {path_value}")
    _require(".." not in candidate.parts, f"{field} must not escape the bundle root: {path_value}")


def _validate_faults(faults):
    _require(isinstance(faults, list), "faults must be a list")
    fault_ids = set()
    for index, fault in enumerate(faults):
        prefix = f"faults[{index}]"
        _require(isinstance(fault, dict), f"{prefix} must be an object")
        _require_non_empty_string(fault.get("fault_id"), f"{prefix}.fault_id")
        _require(fault["fault_id"] not in fault_ids, f"duplicate fault_id {fault['fault_id']}")
        fault_ids.add(fault["fault_id"])
        _require(
            fault.get("category") in ALLOWED_FAULT_CATEGORIES,
            f"{prefix}.category must be one of {sorted(ALLOWED_FAULT_CATEGORIES)}",
        )
        _require(
            fault.get("mode") in ALLOWED_FAULT_MODES,
            f"{prefix}.mode must be one of {sorted(ALLOWED_FAULT_MODES)}",
        )
        _require_non_empty_string(fault.get("target"), f"{prefix}.target")
        _require_non_empty_string(fault.get("trigger"), f"{prefix}.trigger")
        _require(isinstance(fault.get("ts_ms"), int) and fault["ts_ms"] >= 0, f"{prefix}.ts_ms must be >= 0")
        _require_non_empty_string(fault.get("detail"), f"{prefix}.detail")
    return fault_ids


def _validate_files(bundle_root: Path, files):
    _require(isinstance(files, list), "files must be a list")
    seen_paths = set()
    file_kinds = set()
    resolved = {}
    for index, file_record in enumerate(files):
        prefix = f"files[{index}]"
        _require(isinstance(file_record, dict), f"{prefix} must be an object")
        kind = file_record.get("kind")
        _require_non_empty_string(kind, f"{prefix}.kind")
        _require_non_empty_string(file_record.get("label"), f"{prefix}.label")
        relative_path = file_record.get("path")
        _validate_relative_path(relative_path, f"{prefix}.path")
        _require(relative_path not in seen_paths, f"duplicate bundle path {relative_path}")
        seen_paths.add(relative_path)
        file_kinds.add(kind)
        resolved_path = bundle_root / relative_path
        _require(resolved_path.exists(), f"{prefix}.path does not exist: {relative_path}")
        resolved[kind] = resolved_path
    missing = REQUIRED_FILE_KINDS - file_kinds
    _require(not missing, f"bundle is missing required file kinds: {sorted(missing)}")
    return resolved


def _validate_summary(summary):
    _require(isinstance(summary, dict), "summary must be an object")
    _require(summary.get("status") in ALLOWED_SUMMARY_STATUS, f"summary.status must be one of {sorted(ALLOWED_SUMMARY_STATUS)}")
    for field in ("event_count", "reject_count", "injected_fault_count"):
        _require(isinstance(summary.get(field), int) and summary[field] >= 0, f"summary.{field} must be >= 0")


def _validate_event(index: int, event: dict, fault_ids: set[str]):
    prefix = f"events[{index}]"
    _require(isinstance(event, dict), f"{prefix} must be an object")
    _require(event.get("schema_version") == SCHEMA_VERSION, f"{prefix}.schema_version must be {SCHEMA_VERSION}")
    _require_non_empty_string(event.get("event_id"), f"{prefix}.event_id")
    _require(isinstance(event.get("ts_ms"), int) and event["ts_ms"] >= 0, f"{prefix}.ts_ms must be >= 0")
    _require(event.get("domain") in ALLOWED_DOMAINS, f"{prefix}.domain must be one of {sorted(ALLOWED_DOMAINS)}")
    _require_non_empty_string(event.get("component"), f"{prefix}.component")
    _require_non_empty_string(event.get("scenario_name"), f"{prefix}.scenario_name")
    _require(event.get("status") in ALLOWED_EVENT_STATUS, f"{prefix}.status must be one of {sorted(ALLOWED_EVENT_STATUS)}")
    _require_non_empty_string(event.get("kind"), f"{prefix}.kind")

    if event.get("fault_id") is not None:
        _require(event["fault_id"] in fault_ids, f"{prefix}.fault_id must reference a known fault")

    domain = event["domain"]
    if domain == "room":
        _require_non_empty_string(event.get("room_id"), f"{prefix}.room_id")
        _require(isinstance(event.get("room_seq"), int) and event["room_seq"] >= 0, f"{prefix}.room_seq must be >= 0")
        if event["status"] == "rejected":
            _require_non_empty_string(event.get("reject_reason"), f"{prefix}.reject_reason")
    elif domain == "session":
        _require_non_empty_string(event.get("session_id"), f"{prefix}.session_id")
    elif domain == "client":
        _require_non_empty_string(event.get("client_id"), f"{prefix}.client_id")
    elif domain in {"ghostty", "compositor"}:
        _require_non_empty_string(event.get("surface_id"), f"{prefix}.surface_id")
    elif domain == "security":
        _require_non_empty_string(event.get("decision"), f"{prefix}.decision")


def validate_manifest(path: Path):
    manifest = _read_json(path)
    _require(isinstance(manifest, dict), "manifest must be an object")
    _require(manifest.get("schema_version") == SCHEMA_VERSION, f"schema_version must be {SCHEMA_VERSION}")

    scenario = manifest.get("scenario")
    _require(isinstance(scenario, dict), "scenario must be an object")
    _require_non_empty_string(scenario.get("suite"), "scenario.suite")
    _require_non_empty_string(scenario.get("name"), "scenario.name")
    _require_non_empty_string(scenario.get("run_id"), "scenario.run_id")
    if "seed" in scenario:
        _require(isinstance(scenario["seed"], int) and scenario["seed"] >= 0, "scenario.seed must be >= 0")
    if "attempt" in scenario:
        _require(isinstance(scenario["attempt"], int) and scenario["attempt"] >= 1, "scenario.attempt must be >= 1")

    summary = manifest.get("summary")
    _validate_summary(summary)
    fault_ids = _validate_faults(manifest.get("faults"))
    files = _validate_files(path.parent, manifest.get("files"))

    events_path = files["events"]
    summary_path = files["summary"]
    summary_file = _read_json(summary_path)
    _require(summary_file == summary, "summary file content must match manifest.summary")

    event_count = 0
    reject_count = 0
    with events_path.open() as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError as exc:
                raise ValidationError(f"invalid JSONL in {events_path}:{line_number}: {exc}") from exc
            _validate_event(event_count, event, fault_ids)
            event_count += 1
            if event["status"] == "rejected":
                reject_count += 1

    _require(summary["event_count"] == event_count, "summary.event_count does not match transcript")
    _require(summary["reject_count"] == reject_count, "summary.reject_count does not match transcript")
    injected_fault_count = sum(1 for fault in manifest["faults"] if fault["mode"] == "injected")
    _require(
        summary["injected_fault_count"] == injected_fault_count,
        "summary.injected_fault_count does not match faults",
    )


def _make_smoke_bundle():
    scenario = {
        "suite": "verification-artifacts",
        "name": "snapshot-tail-reconnect",
        "run_id": "20260315T000000Z-seed-7",
        "seed": 7,
        "attempt": 1,
    }
    faults = [
        {
            "fault_id": "fault-reconnect-gap",
            "category": "reconnect",
            "mode": "injected",
            "target": "room-gateway",
            "trigger": "drop tail after room_seq 41",
            "ts_ms": 1_710_460_800_010,
            "detail": "force client catch-up from the snapshot boundary",
        },
        {
            "fault_id": "fault-security-deny",
            "category": "security_denial",
            "mode": "observed",
            "target": "terminal-gateway",
            "trigger": "lease holder mismatch",
            "ts_ms": 1_710_460_800_060,
            "detail": "deny stale controller input after reconnect",
        },
    ]
    events = [
        {
            "schema_version": SCHEMA_VERSION,
            "event_id": "evt-room-accept",
            "ts_ms": 1_710_460_800_000,
            "domain": "room",
            "component": "room-actor",
            "scenario_name": scenario["name"],
            "status": "ok",
            "kind": "snapshot_loaded",
            "room_id": "room-1",
            "room_seq": 40,
        },
        {
            "schema_version": SCHEMA_VERSION,
            "event_id": "evt-session-bootstrap",
            "ts_ms": 1_710_460_800_005,
            "domain": "session",
            "component": "terminal-gateway",
            "scenario_name": scenario["name"],
            "status": "ok",
            "kind": "bootstrap_redraw",
            "session_id": "session-1",
        },
        {
            "schema_version": SCHEMA_VERSION,
            "event_id": "evt-client-reconnect",
            "ts_ms": 1_710_460_800_020,
            "domain": "client",
            "component": "room-client",
            "scenario_name": scenario["name"],
            "status": "fault",
            "kind": "reconnect_started",
            "client_id": "client-7",
            "fault_id": "fault-reconnect-gap",
        },
        {
            "schema_version": SCHEMA_VERSION,
            "event_id": "evt-ghostty-redraw",
            "ts_ms": 1_710_460_800_030,
            "domain": "ghostty",
            "component": "ghostty-adapter",
            "scenario_name": scenario["name"],
            "status": "ok",
            "kind": "redraw_completed",
            "surface_id": "surface-1",
        },
        {
            "schema_version": SCHEMA_VERSION,
            "event_id": "evt-compositor-frame",
            "ts_ms": 1_710_460_800_040,
            "domain": "compositor",
            "component": "metal-compositor",
            "scenario_name": scenario["name"],
            "status": "ok",
            "kind": "frame_presented",
            "surface_id": "surface-1",
        },
        {
            "schema_version": SCHEMA_VERSION,
            "event_id": "evt-security-reject",
            "ts_ms": 1_710_460_800_060,
            "domain": "security",
            "component": "terminal-gateway",
            "scenario_name": scenario["name"],
            "status": "rejected",
            "kind": "input_denied",
            "decision": "deny",
            "fault_id": "fault-security-deny",
            "reject_reason": "lease_epoch_mismatch",
        },
    ]
    summary = {
        "status": "failed",
        "event_count": len(events),
        "reject_count": 1,
        "injected_fault_count": 1,
    }
    manifest = {
        "schema_version": SCHEMA_VERSION,
        "scenario": scenario,
        "summary": summary,
        "faults": faults,
        "files": [
            {"kind": "events", "label": "canonical event transcript", "path": "transcripts/events.jsonl"},
            {"kind": "summary", "label": "bundle summary", "path": "summaries/summary.json"},
            {"kind": "failure_log", "label": "retained failure notes", "path": "failures/notes.log"},
        ],
    }
    return manifest, events, summary


def emit_smoke(output_root: Path):
    manifest, events, summary = _make_smoke_bundle()
    bundle_root = output_root / manifest["scenario"]["suite"] / manifest["scenario"]["name"] / manifest["scenario"]["run_id"]
    (bundle_root / "transcripts").mkdir(parents=True, exist_ok=True)
    (bundle_root / "summaries").mkdir(parents=True, exist_ok=True)
    (bundle_root / "failures").mkdir(parents=True, exist_ok=True)
    (bundle_root / "transcripts" / "events.jsonl").write_text(
        "".join(json.dumps(event, sort_keys=True) + "\n" for event in events)
    )
    (bundle_root / "summaries" / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    (bundle_root / "failures" / "notes.log").write_text(
        "fault-reconnect-gap forced reconnect replay from room_seq 41\n"
        "fault-security-deny rejected stale controller input\n"
    )
    manifest_path = bundle_root / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    validate_manifest(manifest_path)
    return manifest_path


def main(argv=None):
    parser = argparse.ArgumentParser(description="Validate or emit canonical verification artifacts.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate_parser = subparsers.add_parser("validate", help="Validate one manifest.json file.")
    validate_parser.add_argument("manifest", type=Path)

    smoke_parser = subparsers.add_parser("smoke", help="Emit a deterministic smoke bundle and validate it.")
    smoke_parser.add_argument("output_root", type=Path)

    args = parser.parse_args(argv)
    try:
        if args.command == "validate":
            validate_manifest(args.manifest)
            print(f"validated {args.manifest}")
        else:
            manifest_path = emit_smoke(args.output_root)
            print(manifest_path)
    except ValidationError as exc:
        print(f"validation error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
