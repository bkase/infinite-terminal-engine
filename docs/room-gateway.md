# Room Gateway

`bd-yas` defines the reconnect-friendly room transport boundary.

## Catch-up contract

Clients connect with an optional `known_room_seq`.

The gateway answers with one of four modes:

- `coldJoin`: no trusted local replica; return the current authoritative snapshot
- `tailOnly`: client already has a valid local snapshot at `known_room_seq`; return only later ops
- `snapshotAndTail`: client is behind the current persisted snapshot boundary; return that snapshot plus later ops
- `upToDate`: client is already at the latest `room_seq`

Rebuild rule:

1. Replace local state with `baseSnapshot` when present.
2. Apply `tailRecords` in ascending `room_seq`.
3. Resume live accepted-op delivery.

This keeps reconnect deterministic without bespoke client repair code.

## Live delivery

Connected clients receive:

- accepted room ops broadcast to all connected clients
- reject payloads returned only to the submitting client
- duplicate-op acknowledgements returned only to the submitting client

Accepted ops stay durable and replayable through the room journal. Rejects are transient client-facing transport feedback and are not written to the durable room stream.

## Scope boundary

The room gateway only carries authoritative spatial state:

- room snapshots
- sequenced room ops
- reject payloads for invalid room ops

It does not place presence chatter or session heartbeat traffic into the durable replay stream. Those remain ephemeral side channels.
