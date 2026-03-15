# Durable Room Schema

`bd-2bd` defines the durable control-plane contract for Step 3.

## Durable truth

Persisted room state includes only:

- room snapshots
- ordered room ops
- session attachment records
- control lease records

It does not include presence, camera viewport, hover, local selection, texture generations, or terminal output bytes.

## Snapshot shape

`DurableRoomSnapshot` stores:

- `schema_version`
- `room_id`
- `room_seq`
- `render_profile_ids`
- `surfaces[]`

Each `DurableRoomSurface` stores:

- `surface_id`
- `session_id?`
- `x_world`, `y_world`
- `cols`, `rows`
- `stack_rank`
- `profile_id`
- `title?`
- `state`
- `created_by`
- `created_at_ms`

The model stays flat, cell-snapped, and authoritative. `stack_rank` is dense room truth, not a client hint.

## Op vocabulary

The durable op set is:

- `create_surface`
- `move_surface`
- `resize_surface`
- `set_stack_rank`
- `close_surface`
- `set_surface_title`
- `attach_session`
- `detach_session`
- `acquire_control`
- `release_control`

All ops serialize through `RoomOpRecord` with `op_id`, `client_id`, `submitted_at_ms`, optional assigned `room_seq`, and a typed payload discriminator.

## Persistence records

Journal and snapshot storage map to these records:

- `RoomOpRecord`: append-only journal row for accepted and replayable control-plane ops
- `RoomSnapshotRecord`: checkpoint row with `room_seq`, `checksum`, and the full durable snapshot blob
- `SessionAttachmentRecord`: current durable attachment metadata for the server-side PTY/session service
- `ControlLeaseRecord`: current control holder, lease epoch, and expiration for one-writer enforcement

Suggested tables:

```text
room_ops(room_id, room_seq, op_id, client_id, submitted_at_ms, payload_json)
room_snapshots(room_id, room_seq, schema_version, checksum, snapshot_json, written_at_ms)
terminal_sessions(session_id, room_id, surface_id, cols, rows, bootstrap_policy, status, updated_at_ms)
control_leases(session_id, holder_user_id, lease_epoch, acquired_at_ms, expires_at_ms)
```

## Migration plan

1. Introduce `schema_version = 1` records and make all writers emit the typed payload discriminator.
2. Start RoomActor work against `RoomOpRecord` and `RoomSnapshotRecord` only; keep presence/viewport in a separate ephemeral channel.
3. On future schema changes, add a new integer `schema_version`, keep snapshot readers backward-compatible long enough to replay old journals, and never silently reinterpret an older payload kind.

## Test lane

```bash
./scripts/test-room.sh
```

The room lane currently validates serialization, payload validation, and empty/populated snapshot compatibility in `RoomSchemaTests`.
