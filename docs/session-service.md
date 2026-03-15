# Session Service

`bd-135` introduces the authoritative PTY session boundary for Step 4.

## Core types

`SessionActor` owns:

- PTY lifecycle state (`provisioning`, `running`, `exited`, `failed`)
- canonical session size
- monotonic `outputSeq`
- subscriber membership and fanout
- failure diagnostics and exit status

`SessionDirectory` provisions and tears down actors by `session_id` so later gateways and lease code do not invent ad hoc socket-local session state.

`PTYBackend` is the runtime seam for real PTY implementations, bootstrap-capable multiplexers, and deterministic test doubles.

## Resource limits

Per-session limits are explicit from day one:

- max cols / rows
- max subscriber count
- max buffered output bytes

Oversize sessions are rejected at construction time. Subscriber overflow is rejected on subscribe. Buffered output overflow transitions the actor to `failed`.

## Delivery model

The actor exposes deterministic deliveries for tests and transport integration:

- `bootstrap`: redraw bytes plus the live-stream anchor
- `output`: ordered byte chunks with inclusive sequence ranges
- `status`: lifecycle transitions with `outputSeq`, `exitCode`, and `failureReason`

## Verification

```bash
./scripts/test-session-service.sh
./scripts/check-session-service.sh
```

Coverage includes lifecycle transitions, output sequence monotonicity, resource-limit failures, directory/subscriber bookkeeping, and an artifact-validated session transcript with per-session logs for provisioning, exit, and forced-failure scenarios.
