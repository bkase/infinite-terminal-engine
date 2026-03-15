# Room Presence

`bd-1qs` keeps viewport and collaborator-awareness traffic out of the durable room log.

## Payload contract

`RoomPresencePayload` carries transient collaboration hints:

- camera origin
- zoom
- viewport size
- optional cursor position
- optional selected surface
- optional control-session display target

These payloads are not written to the room WAL or snapshots.

## Presence hub behavior

`RoomPresenceHub` provides:

- fanout to connected clients
- reconnect snapshots of still-active presence
- TTL-based expiry for stale entries

Presence reconnect and expiry operate entirely on transient state and do not mutate the authoritative room snapshot.

## Verification

```bash
./scripts/test-room-presence.sh
```

Coverage includes fanout smoke, reconnect snapshots, expiry, and proof that presence updates do not change room journal contents.
