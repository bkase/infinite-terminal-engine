# Session Transport

`bd-1vs` adds the Step 4 data-plane contract on top of `SessionActor`.

## Scope

Each subscribed terminal session gets its own transport connection. The transport stays session-local and thin:

- authenticate a scoped session token
- validate the current lease epoch
- emit bootstrap or reconnect replay output
- continue streaming live output and status changes
- emit an explicit `lease_revoked` event when the authenticated epoch is no longer current

## Protocol shape

The host-side transport models the V1 WebSocket contract from `history/eng-plan.md`:

- `C->S Auth(token, session_id, lease_epoch)`
- `C->S InputBytes(client_input_seq, bytes)`
- `S->C Bootstrap(output_seq_start, output_seq_end, bytes)`
- `S->C Output(output_seq_start, bytes)`
- `S->C Status(status, output_seq, exit_code?, failure_reason?)`
- `S->C LeaseRevoked(previous_lease_epoch, current_lease_epoch)`

## Reconnect

Reconnect accepts an optional `reconnect_after_output_seq` anchor.

- If the anchor is current, the transport replays only the missing output tail and then emits the latest status.
- If the anchor is ahead of the session's retained output, the transport falls back to bootstrap and records a `stale_anchor` diagnostic line.

`bd-3rr` layers a client-side `SessionClient` on top of this transport:

- subscribe creates a fresh surface adapter and ingests bootstrap before live bytes
- reconnect also creates a fresh adapter and intentionally requests a new bootstrap so replay never targets a stale adapter instance
- per-surface `overlayText` stays local to the affected surface for disconnected or failed session states

## Diagnostics

Each connection produces deterministic log lines with:

- connection id
- session id and client id
- authenticated lease epoch
- resume mode (`bootstrap`, `replay`, or `staleAnchorBootstrap`)
- per-message summaries for bootstrap, output, status, lease revocation, and client input

## Verification

```bash
./scripts/test-session-transport.sh
./scripts/check-session-transport.sh
./scripts/check-session-client.sh
```

Coverage includes token success/failure, bootstrap ordering, reconnect replay, stale-anchor fallback, lease-revocation delivery, and client-side bootstrap/live/reconnect/failure overlay handling.
