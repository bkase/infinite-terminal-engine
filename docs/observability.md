# Observability

`bd-25y` adds one shared observability surface for room, session, Ghostty, and compositor paths.

## Signals

The host now emits:

- metrics through `Observability.metric(...)`
- structured logs through `Observability.log(...)`

Stable metric names currently include:

- `room.connect_total`
- `room.apply_total`
- `room.reject_total`
- `session.transport_connect_total`
- `session.input_bytes`
- `session.lease_revoked_total`
- `ghostty.paste_bytes`
- `ghostty.resize_total`
- `ghostty.texture_publish_total`
- `compositor.visible_surfaces`
- `compositor.occluded_surfaces`
- `compositor.texture_memory_bytes`
- `compositor.frame_build_micros`
- `compositor.frame_render_millis`

## Smoke path

```bash
./scripts/check-observability.sh
```

This runs `ObservabilityTests`, emits a retained artifact bundle, and validates the canonical `manifest.json`.

## Artifact layout

The smoke bundle lands under:

```text
<artifact-root>/observability/observability-smoke/20260315T000000Z-seed-301/
```

It retains:

- canonical `events.jsonl` and `summary.json`
- `logs/metrics.json`
- `logs/logs.json`

The retained payloads are intentionally machine-readable so replay, soak, and release lanes can consume the same fields without adapter-specific parsing.
