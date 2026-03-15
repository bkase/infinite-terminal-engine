#!/usr/bin/env python3
import argparse
import base64
import json
import sys
from pathlib import Path


class ReplayError(Exception):
    pass


def _identifier(value):
    if isinstance(value, str):
        return value
    if isinstance(value, dict) and isinstance(value.get("rawValue"), str):
        return value["rawValue"]
    raise ReplayError(f"expected identifier string or rawValue object, got {value!r}")


def _read_json(path: Path):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError as exc:
        raise ReplayError(f"missing file: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ReplayError(f"invalid JSON in {path}: {exc}") from exc


def _load_manifest(path: Path):
    manifest = _read_json(path)
    if not isinstance(manifest, dict):
        raise ReplayError("manifest must be an object")
    files = manifest.get("files")
    if not isinstance(files, list):
        raise ReplayError("manifest.files must be a list")
    file_map = {}
    for file_record in files:
        kind = file_record.get("kind")
        relative_path = file_record.get("path")
        if isinstance(kind, str) and isinstance(relative_path, str):
            file_map[kind] = path.parent / relative_path
    return manifest, file_map


def _decode_bytes(payload: dict, prefix: str):
    base64_value = payload.get("bytes_base64")
    if not isinstance(base64_value, str) or not base64_value:
        raise ReplayError(f"{prefix}.bytes_base64 must be a non-empty string")
    try:
        return base64.b64decode(base64_value)
    except ValueError as exc:
        raise ReplayError(f"{prefix}.bytes_base64 is not valid base64") from exc


def _first_diff(expected, actual, path="root"):
    if type(expected) is not type(actual):
        return f"{path}: type mismatch expected {type(expected).__name__} got {type(actual).__name__}"
    if isinstance(expected, dict):
        expected_keys = sorted(expected.keys())
        actual_keys = sorted(actual.keys())
        if expected_keys != actual_keys:
            return f"{path}: key mismatch expected {expected_keys} got {actual_keys}"
        for key in expected_keys:
            diff = _first_diff(expected[key], actual[key], f"{path}.{key}")
            if diff:
                return diff
        return None
    if isinstance(expected, list):
        if len(expected) != len(actual):
            return f"{path}: length mismatch expected {len(expected)} got {len(actual)}"
        for index, (expected_item, actual_item) in enumerate(zip(expected, actual)):
            diff = _first_diff(expected_item, actual_item, f"{path}[{index}]")
            if diff:
                return diff
        return None
    if expected != actual:
        return f"{path}: expected {expected!r} got {actual!r}"
    return None


def replay_room(manifest_path: Path, check: bool):
    manifest, files = _load_manifest(manifest_path)
    snapshot_path = files.get("room_snapshot")
    journal_path = files.get("room_journal")
    if snapshot_path is None or journal_path is None:
        raise ReplayError("manifest must include room_snapshot and room_journal files")

    current = _read_json(snapshot_path)
    records = _read_json(journal_path)
    if not isinstance(current, dict):
        raise ReplayError("room_snapshot payload must be an object")
    if not isinstance(records, list):
        raise ReplayError("room_journal payload must be an array")

    surfaces = [dict(surface) for surface in current.get("surfaces", [])]
    render_profile_ids = list(current.get("renderProfileIDs", []))
    control_leases = list(current.get("controlLeases", []))
    room_id = _identifier(current.get("roomID"))
    room_seq = current.get("roomSeq")

    surface_by_id = {_identifier(surface["id"]): surface for surface in surfaces}

    def resequence():
        ordered = sorted(surface_by_id.values(), key=lambda surface: surface["stackRank"])
        for index, surface in enumerate(ordered):
            surface["stackRank"] = index
        return ordered

    for index, record in enumerate(records):
        payload = record.get("payload")
        if not isinstance(payload, dict):
            raise ReplayError(f"room_journal[{index}].payload must be an object")
        kind = payload.get("kind")
        body = payload.get("payload", {})
        if kind == "create_surface":
            surface = {
                "id": body["surfaceID"],
                "sessionID": None,
                "xWorld": body["xWorld"],
                "yWorld": body["yWorld"],
                "cols": body["cols"],
                "rows": body["rows"],
                "stackRank": len(surface_by_id),
                "profileID": body["profileID"],
                "title": None,
                "state": "provisioning",
                "createdBy": {"rawValue": "client-generated"},
                "createdAtMillis": record["submittedAtMillis"],
            }
            surface_by_id[_identifier(surface["id"])] = surface
        elif kind == "move_surface":
            surface_by_id[_identifier(body["surfaceID"])]["xWorld"] = body["xWorld"]
            surface_by_id[_identifier(body["surfaceID"])]["yWorld"] = body["yWorld"]
        elif kind == "resize_surface":
            surface_by_id[_identifier(body["surfaceID"])]["cols"] = body["cols"]
            surface_by_id[_identifier(body["surfaceID"])]["rows"] = body["rows"]
        elif kind == "set_stack_rank":
            ordered = resequence()
            surface_id = _identifier(body["surfaceID"])
            moving = next(surface for surface in ordered if _identifier(surface["id"]) == surface_id)
            ordered = [surface for surface in ordered if _identifier(surface["id"]) != surface_id]
            target_rank = min(max(body["targetRank"], 0), len(ordered))
            ordered.insert(target_rank, moving)
            for rank, surface in enumerate(ordered):
                surface["stackRank"] = rank
                surface_by_id[_identifier(surface["id"])] = surface
        elif kind == "close_surface":
            surface_by_id.pop(_identifier(body["surfaceID"]), None)
            ordered = resequence()
            surface_by_id.clear()
            for surface in ordered:
                surface_by_id[_identifier(surface["id"])] = surface
        elif kind == "set_surface_title":
            surface_by_id[_identifier(body["surfaceID"])]["title"] = body.get("title")
        elif kind == "attach_session":
            surface = surface_by_id[_identifier(body["surfaceID"])]
            surface["sessionID"] = body["sessionID"]
            surface["state"] = "attached"
        elif kind == "detach_session":
            surface = surface_by_id[_identifier(body["surfaceID"])]
            surface["sessionID"] = None
            surface["state"] = "disconnected"
        elif kind == "acquire_control":
            next_epoch = 1
            for lease in control_leases:
                if _identifier(lease["sessionID"]) == _identifier(body["sessionID"]):
                    next_epoch = max(next_epoch, lease["leaseEpoch"] + 1)
            control_leases = [
                lease for lease in control_leases if _identifier(lease["sessionID"]) != _identifier(body["sessionID"])
            ]
            control_leases.append({
                "sessionID": body["sessionID"],
                "holderUserID": body["holderUserID"],
                "leaseEpoch": next_epoch,
                "acquiredAtMillis": record["submittedAtMillis"],
                "expiresAtMillis": record["submittedAtMillis"] + 30_000,
            })
            control_leases = sorted(control_leases, key=lambda lease: _identifier(lease["sessionID"]))
        elif kind == "release_control":
            control_leases = [
                lease for lease in control_leases if _identifier(lease["sessionID"]) != _identifier(body["sessionID"])
            ]
        else:
            raise ReplayError(f"unsupported room payload kind: {kind}")

        if record.get("roomSeq") is not None:
            room_seq = record["roomSeq"]

    result = {
        "schemaVersion": current["schemaVersion"],
        "roomID": room_id,
        "roomSeq": room_seq,
        "renderProfileIDs": render_profile_ids,
        "surfaces": resequence(),
        "controlLeases": control_leases,
    }

    if check:
        expected_path = files.get("room_expected_snapshot")
        if expected_path is None:
            raise ReplayError("manifest must include room_expected_snapshot when --check is used")
        expected = _read_json(expected_path)
        diff = _first_diff(expected, result)
        if diff:
            raise ReplayError(f"room replay diverged: {diff}")

    output = {
        "scenario": manifest.get("scenario", {}),
        "result": result,
    }
    print(json.dumps(output, indent=2, sort_keys=True))


def replay_session(manifest_path: Path, check: bool):
    manifest, files = _load_manifest(manifest_path)
    bootstrap_path = files.get("session_bootstrap")
    output_path = files.get("session_output")
    if bootstrap_path is None or output_path is None:
        raise ReplayError("manifest must include session_bootstrap and session_output files")

    bootstrap = _read_json(bootstrap_path)
    chunks = _read_json(output_path)
    if not isinstance(bootstrap, dict):
        raise ReplayError("session_bootstrap payload must be an object")
    if not isinstance(chunks, list):
        raise ReplayError("session_output payload must be an array")

    bytes_out = bytearray(_decode_bytes(bootstrap, "session_bootstrap"))
    expected_next_seq = int(bootstrap.get("output_seq_end", 0)) + 1
    replayed_chunks = []
    for index, chunk in enumerate(chunks):
        if not isinstance(chunk, dict):
            raise ReplayError(f"session_output[{index}] must be an object")
        seq_start = chunk.get("seq_start")
        seq_end = chunk.get("seq_end")
        if not isinstance(seq_start, int) or not isinstance(seq_end, int):
            raise ReplayError(f"session_output[{index}] must include integer seq_start/seq_end")
        if seq_start != expected_next_seq:
            raise ReplayError(
                f"session_output[{index}] expected seq_start {expected_next_seq} but found {seq_start}"
            )
        if seq_end < seq_start:
            raise ReplayError(f"session_output[{index}] has seq_end before seq_start")
        chunk_bytes = _decode_bytes(chunk, f"session_output[{index}]")
        bytes_out.extend(chunk_bytes)
        expected_next_seq = seq_end + 1
        replayed_chunks.append({
            "seq_start": seq_start,
            "seq_end": seq_end,
            "byte_count": len(chunk_bytes),
        })

    result = {
        "session_id": bootstrap.get("session_id"),
        "output_seq_end": expected_next_seq - 1,
        "bytes_utf8": bytes_out.decode("utf-8"),
        "bytes_base64": base64.b64encode(bytes(bytes_out)).decode("ascii"),
        "chunks": replayed_chunks,
    }

    if check:
        expected_path = files.get("session_expected_output")
        if expected_path is None:
            raise ReplayError("manifest must include session_expected_output when --check is used")
        expected = _read_json(expected_path)
        comparable = {
            "session_id": result["session_id"],
            "bytes_utf8": result["bytes_utf8"],
            "bytes_base64": result["bytes_base64"],
        }
        diff = _first_diff(expected, comparable)
        if diff:
            raise ReplayError(f"session replay diverged: {diff}")

    output = {
        "scenario": manifest.get("scenario", {}),
        "result": result,
    }
    print(json.dumps(output, indent=2, sort_keys=True))


def main(argv=None):
    parser = argparse.ArgumentParser(description="Replay retained room and session artifacts offline.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    room_parser = subparsers.add_parser("room", help="Replay a room bundle from retained snapshot + journal.")
    room_parser.add_argument("manifest", type=Path)
    room_parser.add_argument("--check", action="store_true", help="Diff the replay result against room_expected_snapshot.")

    session_parser = subparsers.add_parser("session", help="Replay a session bundle from retained bootstrap + output.")
    session_parser.add_argument("manifest", type=Path)
    session_parser.add_argument("--check", action="store_true", help="Diff the replay result against session_expected_output.")

    args = parser.parse_args(argv)
    try:
        if args.command == "room":
            replay_room(args.manifest, args.check)
        else:
            replay_session(args.manifest, args.check)
    except ReplayError as exc:
        print(f"replay error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
