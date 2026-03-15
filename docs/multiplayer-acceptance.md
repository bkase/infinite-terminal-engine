# Multiplayer Acceptance

`bd-32x` adds one authoritative multiplayer acceptance lane for Step 4.

## Coverage

The suite exercises stable scenario slugs under the `multiplayer` artifact suite:

- `shared-view-one-writer`
- `late-join-bootstrap-live`
- `room-reconnect-live-session`
- `session-reconnect-replay`
- `session-outage-live-room`

Together these cover shared viewing, one-writer leases, late join bootstrap, room reconnect, session reconnect, and plane-isolated failure handling.

## Run locally

```bash
./scripts/test-multiplayer.sh
```

The script runs `MultiplayerAcceptanceTests`, keeps retained artifacts on disk, and validates every emitted `manifest.json` with the canonical verification tool.

To control where artifacts land:

```bash
ITE_MULTIPLAYER_ARTIFACT_ROOT=/tmp/ite-multiplayer ./scripts/test-multiplayer.sh
```

## Retained artifacts

Each scenario writes a canonical bundle under:

```text
<artifact-root>/multiplayer/<scenario-name>/<run-id>/
```

Bundles include:

- `manifest.json`
- `transcripts/events.jsonl`
- `summaries/summary.json`
- scenario logs under `logs/`

The logs are intentionally split by plane or client so failures can be narrowed without re-running ad hoc local experiments.
