# Control Leases

`bd-128` hardens Step 4's one-writer rule across the room and session services.

## Contract

The room plane stays authoritative for shared lease state:

- `AcquireControl(session_id, holder_user_id)` grants the lease only when the session is attached and currently free for another holder
- `ReleaseControl(session_id)` clears the active lease for an attached session
- accepted lease changes persist as `ControlLeaseRecord` values in the durable snapshot

The session plane enforces the resulting epoch:

- session transport auth requires the current `lease_epoch`
- input is rejected if the authenticated epoch becomes stale
- stale writers receive an explicit `lease_revoked` message

## Conflict semantics

- Acquiring control for an unattached session is rejected.
- Acquiring control while another user holds the lease is rejected.
- Reacquiring control by the current holder is treated as a no-op, which preserves the current epoch and avoids unnecessary client revocation.

## Client-facing updates

`RoomGateway` now broadcasts explicit `leaseUpdated(sessionID, leaseRecord?)` ephemeral deliveries whenever a lease is granted or released. This gives clients a lease-state update channel without putting terminal input on the room sequencer.

## Verification

```bash
./scripts/test-control-leases.sh
./scripts/check-control-leases.sh
```

Coverage includes competing-writer rejection, snapshot recovery with monotonic epochs, gateway lease update fanout, and forced transport revocation after an epoch change.
