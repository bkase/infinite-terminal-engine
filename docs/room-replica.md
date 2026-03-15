# Room Replica

`bd-1dk` adds the optimistic client-side room replica.

## Responsibilities

`RoomReplica` keeps:

- `authoritativeSnapshot`: the last sequenced room state from the gateway
- `predictedSnapshot`: authoritative state plus locally pending optimistic ops
- `pendingOps`: the client-side queue waiting for accept or reject
- `timeline`: readable per-op reconciliation notes for debugging

## Reconciliation rules

1. Local submission generates a client-scoped `op_id`.
2. The replica appends the pending op and rebuilds `predictedSnapshot`.
3. Authoritative accepts advance `authoritativeSnapshot`, remove matching pending ops, and rebase the remaining queue.
4. Rejects remove the matching pending op and rebuild prediction from authoritative truth.
5. Out-of-order authoritative deliveries buffer until `room_seq` becomes contiguous.

## Verification

```bash
./scripts/test-room-replica.sh
```

Coverage includes optimistic accept, reject rollback, pending-op rebase, duplicate authoritative delivery, and out-of-order authoritative delivery.
