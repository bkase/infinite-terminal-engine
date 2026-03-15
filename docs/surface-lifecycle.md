# Surface Lifecycle

`bd-2bz` defines one derived surface lifecycle across room, session, and client state.

## States

- `provisioning`: room surface exists but the session and client path are not fully attached yet
- `attached`: room surface is attached, session is running, and all subscribed clients are live
- `disconnected`: room or session detached cleanly
- `degraded`: room and session still exist, but at least one subscribed client is disconnected or failed locally
- `error`: the session plane failed while the room surface is still present
- `closing`: teardown is in progress or the room surface has already been removed

## Derivation

`SurfaceLifecycleCoordinator` is the only place that derives this phase:

- room state comes from `RoomActor` / `RoomGateway`
- session state comes from `SessionDirectory` / `SessionActor`
- client state comes from each subscribed `SessionClient`

This keeps cross-service policy out of ad hoc UI callbacks.

## Verification

```bash
./Scripts/swiftpm-cache.sh test --filter SurfaceLifecycleCoordinatorTests
./scripts/check-surface-lifecycle.sh
```

Coverage includes create-to-attach, close teardown, room-up/session-down failure, room-up/client-down degradation, and multi-view shared-surface attachment.
