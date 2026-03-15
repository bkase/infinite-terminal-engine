# Session Service

`bd-135` introduces the authoritative PTY session boundary for Step 4.

## Core types

`SessionActor` owns:

- PTY lifecycle state (`provisioning`, `running`, `exited`, `failed`)
- canonical session size
- authoritative resize reconciliation (`desired`, `applied`, `acknowledged`, `failed`)
- monotonic `outputSeq`
- subscriber membership and fanout
- failure diagnostics and exit status

`SessionDirectory` provisions and tears down actors by `session_id` so later gateways and lease code do not invent ad hoc socket-local session state.

`PTYBackend` is the runtime seam for real PTY implementations, bootstrap-capable multiplexers, and deterministic test doubles.

`ReplayLogPTYBackend` is the first bootstrap-capable prototype adapter. It retains a session-local transcript of ordered output and resize history, emits bootstrap redraw bytes by replaying retained output, and leaves the backend pluggable for a stronger redraw source later.

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
- `status.resize`: desired-vs-actual resize state so clients can surface lag or failed PTY application explicitly

For reconnect and late join, `SessionActor.outputChunks(after:)` slices output by arbitrary anchors, including mid-chunk anchors, so continuation does not depend on transport chunk boundaries.

## Verification

```bash
./scripts/test-session-service.sh
./scripts/check-session-service.sh
./scripts/check-authoritative-resize.sh
```

Coverage includes lifecycle transitions, output sequence monotonicity, resource-limit failures, directory/subscriber bookkeeping, authoritative resize reconciliation, and artifact-validated transcripts for provisioning, exit, forced-failure, and resize-lag scenarios.
