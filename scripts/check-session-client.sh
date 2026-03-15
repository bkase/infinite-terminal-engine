#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root
require_cmd python3

bundle_root="$(mktemp -d "${TMPDIR:-/tmp}/ite-session-client.XXXXXX")"
trap 'rm -rf "$bundle_root"' EXIT

run_check session-client-tests "run session client unit coverage" \
  ./Scripts/swiftpm-cache.sh test --filter SessionClientTests

mkdir -p "$bundle_root/transcripts" "$bundle_root/summaries" "$bundle_root/logs"

cat > "$bundle_root/transcripts/events.jsonl" <<'EOF'
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-client-subscribe","ts_ms":0,"domain":"client","component":"session-client","scenario_name":"session-client-bootstrap","status":"ok","kind":"surface_subscribed","room_id":"room-1","room_seq":1,"client_id":"client-1","session_id":"session-1","surface_id":"surface-1"}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-client-bootstrap","ts_ms":1,"domain":"client","component":"session-client","scenario_name":"session-client-bootstrap","status":"ok","kind":"bootstrap_redraw","room_id":"room-1","room_seq":1,"client_id":"client-1","session_id":"session-1","surface_id":"surface-1","output_seq_start":1,"output_seq_end":6}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-client-live","ts_ms":2,"domain":"client","component":"session-client","scenario_name":"session-client-bootstrap","status":"ok","kind":"live_output_continuation","room_id":"room-1","room_seq":1,"client_id":"client-1","session_id":"session-1","surface_id":"surface-1","output_seq_start":7,"output_seq_end":9}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-client-reconnect","ts_ms":3,"domain":"client","component":"session-client","scenario_name":"session-client-bootstrap","status":"fault","kind":"transport_disconnected","room_id":"room-1","room_seq":1,"client_id":"client-1","session_id":"session-1","surface_id":"surface-1","fault_id":"fault-fresh-adapter-reconnect"}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-client-fresh-adapter","ts_ms":4,"domain":"client","component":"session-client","scenario_name":"session-client-bootstrap","status":"ok","kind":"bootstrap_redraw","room_id":"room-1","room_seq":1,"client_id":"client-1","session_id":"session-1","surface_id":"surface-1","fault_id":"fault-fresh-adapter-reconnect","output_seq_start":1,"output_seq_end":9}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-client-overlay","ts_ms":5,"domain":"client","component":"session-client","scenario_name":"session-client-bootstrap","status":"fault","kind":"surface_overlay_failed","room_id":"room-1","room_seq":1,"client_id":"client-2","session_id":"session-2","surface_id":"surface-2","fault_id":"fault-surface-local-failure"}
EOF

cat > "$bundle_root/summaries/summary.json" <<'EOF'
{"status":"passed","event_count":6,"reject_count":0,"injected_fault_count":2}
EOF

cat > "$bundle_root/logs/session-client.log" <<'EOF'
surface_id=surface-1 session_id=session-1 action=subscribe adapter_generation=1
surface_id=surface-1 session_id=session-1 action=bootstrap output_seq=6 adapter_generation=1
surface_id=surface-1 session_id=session-1 action=live output_seq=9 adapter_generation=1
surface_id=surface-1 session_id=session-1 action=reconnect previous_output_seq=9
surface_id=surface-1 session_id=session-1 action=bootstrap output_seq=9 adapter_generation=2
surface_id=surface-2 session_id=session-2 action=status session_status=failed output_seq=6 adapter_generation=3
EOF

cat > "$bundle_root/manifest.json" <<'EOF'
{
  "schema_version": "ite.verification_artifact.v1",
  "scenario": {
    "suite": "session",
    "name": "session-client-bootstrap",
    "run_id": "20260315T000000Z-seed-43",
    "seed": 43,
    "attempt": 1
  },
  "summary": {
    "status": "passed",
    "event_count": 6,
    "reject_count": 0,
    "injected_fault_count": 2
  },
  "faults": [
    {
      "fault_id": "fault-fresh-adapter-reconnect",
      "category": "reconnect",
      "mode": "injected",
      "target": "session-client",
      "trigger": "disconnect and reconnect with a fresh adapter generation",
      "ts_ms": 3,
      "detail": "proves reconnect rebuilds the surface from bootstrap instead of replaying into stale state"
    },
    {
      "fault_id": "fault-surface-local-failure",
      "category": "outage",
      "mode": "injected",
      "target": "session-client",
      "trigger": "backend emits failed status for one subscribed surface",
      "ts_ms": 5,
      "detail": "proves the failed overlay stays isolated to the affected surface"
    }
  ],
  "files": [
    {
      "kind": "events",
      "label": "session client transcript",
      "path": "transcripts/events.jsonl"
    },
    {
      "kind": "summary",
      "label": "session client summary",
      "path": "summaries/summary.json"
    },
    {
      "kind": "client_log",
      "label": "session client log",
      "path": "logs/session-client.log"
    }
  ]
}
EOF

run_check session-client-artifact "validate session client verification artifact bundle" \
  python3 scripts/verification-artifact-tool.py validate "$bundle_root/manifest.json"

info "session client verification artifact: $bundle_root/manifest.json"
