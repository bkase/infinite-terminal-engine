# Room Formal Model

`bd-1bd` adds a small-state formal model for the durable room control plane.

## Covered invariants

The model checks:

- monotonic `room_seq`
- unique `surface_id`
- dense total order over `stack_rank`
- unique `session_id` attachment across surfaces
- at most one active lease per `session_id`
- idempotent replay by `op_id`
- snapshot + tail replay equivalence

The model intentionally ignores PTY byte-stream behavior and other data-plane concerns.

## Implementation tie-in

`RoomFormalModelTests` defines a reference state machine in the test target and cross-checks it against the implementation over a bounded operation catalog that includes:

- create
- move
- resize
- reorder
- attach
- acquire/release lease
- duplicate `op_id` replay

The replay-equivalence test splits accepted transcripts at a snapshot boundary and proves `snapshot + tail` reconstruction matches uninterrupted execution.

## Slow-lane entrypoint

```bash
./scripts/check-room-model.sh
```

This script:

1. runs `RoomFormalModelTests`
2. captures raw output to a retained artifact bundle
3. emits a canonical verification manifest under `.build/verification-artifacts/room/room-formal-model/<run-id>/`

`scripts/verify-demo.sh` includes this lane so the formal model runs in the slower verification path instead of the fast commit gate.
