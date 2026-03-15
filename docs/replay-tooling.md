# Replay Tooling

`bd-ewp` adds an offline replay path for the two retained planes that are hardest to debug live:

- room replay from persisted snapshot + journal tail
- session replay from bootstrap redraw bytes + ordered output chunks

## Entry points

Validate replay payloads from a retained bundle:

```bash
python3 ./scripts/replay-artifact-tool.py room path/to/manifest.json --check
python3 ./scripts/replay-artifact-tool.py session path/to/manifest.json --check
```

Run the repo regression path against artifacts emitted by the real multiplayer reconnect suite:

```bash
./scripts/test-replay-artifacts.sh
```

The script reruns `MultiplayerAcceptanceTests`, keeps the retained bundles on disk long enough to inspect them, and then proves:

- `room-reconnect-live-session` can rebuild the final room snapshot from `room_snapshot` + `room_journal`
- `session-reconnect-replay` can rebuild the final session output from `session_bootstrap` + `session_output`

## Bundle contract

Replay-capable manifests keep the normal `events` and `summary` files plus these optional `files[].kind` entries:

- `room_snapshot`
- `room_journal`
- `room_expected_snapshot`
- `session_bootstrap`
- `session_output`
- `session_expected_output`

The payloads remain normal retained bundle files under `replay/`; there is no replay-only side channel outside the canonical artifact bundle.
