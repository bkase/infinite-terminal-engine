#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root
require_cmd python3

bundle_root="$(mktemp -d "${TMPDIR:-/tmp}/ite-control-leases.XXXXXX")"
trap 'rm -rf "$bundle_root"' EXIT

run_check control-leases-tests "run room/session lease coverage" ./scripts/test-control-leases.sh

mkdir -p "$bundle_root/transcripts" "$bundle_root/summaries" "$bundle_root/logs"

cat > "$bundle_root/transcripts/events.jsonl" <<'EOF'
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-lease-granted","ts_ms":0,"domain":"room","component":"room-gateway","scenario_name":"control-lease-conflict-and-revocation","status":"ok","kind":"lease_granted","room_id":"room-1","room_seq":3,"session_id":"session-1"}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-lease-conflict","ts_ms":1,"domain":"room","component":"room-gateway","scenario_name":"control-lease-conflict-and-revocation","status":"fault","kind":"lease_conflict","room_id":"room-1","room_seq":3,"session_id":"session-1","fault_id":"fault-competing-writer"}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-lease-epoch-change","ts_ms":2,"domain":"room","component":"room-actor","scenario_name":"control-lease-conflict-and-revocation","status":"ok","kind":"lease_epoch_incremented","room_id":"room-1","room_seq":5,"session_id":"session-1","output_seq_start":0,"output_seq_end":0}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-transport-revoked","ts_ms":3,"domain":"session","component":"session-transport","scenario_name":"control-lease-conflict-and-revocation","status":"fault","kind":"lease_revoked","room_id":"room-1","session_id":"session-1","fault_id":"fault-competing-writer"}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-stale-input-rejected","ts_ms":4,"domain":"session","component":"session-transport","scenario_name":"control-lease-conflict-and-revocation","status":"fault","kind":"input_rejected","room_id":"room-1","session_id":"session-1","fault_id":"fault-stale-epoch"}
EOF

cat > "$bundle_root/summaries/summary.json" <<'EOF'
{"status":"passed","event_count":5,"reject_count":0,"injected_fault_count":2}
EOF

cat > "$bundle_root/logs/room-lease.log" <<'EOF'
session_id=session-1 holder=user-1 lease_epoch=1 status=granted
session_id=session-1 holder=user-2 status=rejected reason=control_lease_held_by_another_user
session_id=session-1 holder=user-2 lease_epoch=2 status=granted
EOF

cat > "$bundle_root/logs/session-transport.log" <<'EOF'
connection_id=session-session-1-conn-1 session_id=session-1 client_id=client-1 auth=ok lease_epoch=1
connection_id=session-session-1-conn-1 direction=s2c type=lease_revoked previous_epoch=1 current_epoch=2
connection_id=session-session-1-conn-1 direction=c2s type=input client_input_seq=1 bytes=3 rejected=lease_revoked
EOF

cat > "$bundle_root/manifest.json" <<'EOF'
{
  "schema_version": "ite.verification_artifact.v1",
  "scenario": {
    "suite": "multiplayer",
    "name": "control-lease-conflict-and-revocation",
    "run_id": "20260315T000000Z-seed-41",
    "seed": 41,
    "attempt": 1
  },
  "summary": {
    "status": "passed",
    "event_count": 5,
    "reject_count": 0,
    "injected_fault_count": 2
  },
  "faults": [
    {
      "fault_id": "fault-competing-writer",
      "category": "lease",
      "mode": "injected",
      "target": "room-gateway",
      "trigger": "second user acquires already-held lease",
      "ts_ms": 1,
      "detail": "room actor rejects the competing writer and preserves the current holder"
    },
    {
      "fault_id": "fault-stale-epoch",
      "category": "lease",
      "mode": "injected",
      "target": "session-transport",
      "trigger": "writer continues sending input after epoch changes",
      "ts_ms": 4,
      "detail": "transport rejects stale input and keeps the data plane session-local"
    }
  ],
  "files": [
    {
      "kind": "events",
      "label": "lease event transcript",
      "path": "transcripts/events.jsonl"
    },
    {
      "kind": "summary",
      "label": "lease summary",
      "path": "summaries/summary.json"
    },
    {
      "kind": "room_log",
      "label": "room lease log",
      "path": "logs/room-lease.log"
    },
    {
      "kind": "session_log",
      "label": "session transport lease log",
      "path": "logs/session-transport.log"
    }
  ]
}
EOF

run_check control-leases-artifact "validate control lease verification artifact bundle" \
  python3 scripts/verification-artifact-tool.py validate "$bundle_root/manifest.json"

info "control lease verification artifact: $bundle_root/manifest.json"
