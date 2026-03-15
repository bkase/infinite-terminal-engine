# Verification Artifacts

`bd-3tw` defines the canonical retained verification bundle for room, session, client, Ghostty, compositor, and security checks.

## Schema version

Every bundle and every event record carries:

- `schema_version = "ite.verification_artifact.v1"`

Writers must only emit one schema version per bundle. Future versions must add a new string and keep old readers gated by explicit version checks instead of silently reinterpreting payloads.

## Bundle layout

Retained artifacts live under:

```text
artifacts/<suite>/<scenario-name>/<run-id>/
```

The canonical files are:

- `manifest.json`: top-level scenario metadata, fault list, summary rollup, and relative file references
- `transcripts/events.jsonl`: machine-readable event stream, one JSON object per line
- `summaries/summary.json`: rolled-up pass/fail counters copied from `manifest.json`
- `failures/*.log`: human-readable retained debugging notes for failures or injected faults

Bundle paths must stay relative, deterministic, and safe to archive. Producers must not emit absolute paths or `..` segments.

## Scenario naming

`manifest.json` stores:

- `scenario.suite`: the higher-level verification lane such as `room`, `multiplayer`, `release`, or `security`
- `scenario.name`: a stable scenario slug such as `snapshot-tail-reconnect`
- `scenario.run_id`: a deterministic run identifier such as `20260315T000000Z-seed-7`
- optional `scenario.seed`
- optional `scenario.attempt`

Use the scenario slug in transcript names and log headings so retained failures stay searchable across scripts and CI artifacts.

## Event contract

Each event in `transcripts/events.jsonl` includes:

- `schema_version`
- `event_id`
- `ts_ms`
- `domain`: one of `room`, `session`, `client`, `ghostty`, `compositor`, `security`
- `component`: producer name such as `room-actor` or `metal-compositor`
- `scenario_name`
- `status`: one of `ok`, `rejected`, `fault`
- `kind`

Domain-specific required fields:

- `room`: `room_id`, `room_seq`, and `reject_reason` when `status = rejected`
- `session`: `session_id`
- `client`: `client_id`
- `ghostty`: `surface_id`
- `compositor`: `surface_id`
- `security`: `decision`

Shared correlation fields are optional but recommended whenever available:

- `op_id`
- `fault_id`
- `surface_id`
- `session_id`
- `client_id`

## Fault-injection contract

`manifest.json` stores a canonical `faults[]` list. Each record includes:

- `fault_id`
- `category`: one of `reconnect`, `lease`, `outage`, `redraw`, `security_denial`
- `mode`: `injected` or `observed`
- `target`
- `trigger`
- `ts_ms`
- `detail`

Any event that was caused by an injected or observed fault should reference the same `fault_id`. This is the stable join key for reconnect gaps, lease races, redraw stalls, transport outages, and security-denial scenarios.

## Summary rollup

`manifest.json` and `summaries/summary.json` both store:

- `status`: `passed` or `failed`
- `event_count`
- `reject_count`
- `injected_fault_count`

Writers must keep the summary counts consistent with the event transcript and fault list. The validator rejects bundles where the rollup diverges from the retained files.

## Validation and smoke test

Use the shared tool for future harnesses:

```bash
python3 ./scripts/verification-artifact-tool.py validate path/to/manifest.json
python3 ./scripts/verification-artifact-tool.py smoke /tmp/ite-artifacts
```

The smoke command emits a deterministic sample bundle that covers room, session, client, Ghostty, compositor, and security events plus reconnect and security-denial faults.

## Triage flow

1. Open `manifest.json` to identify the scenario and retained file paths.
2. Read `summaries/summary.json` for pass/fail counts and reject totals.
3. Scan `transcripts/events.jsonl` by `fault_id`, `room_seq`, `op_id`, or `session_id`.
4. Use `failures/*.log` for human-readable notes only after the machine-readable transcript has narrowed the incident.
