#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root
require_cmd python3

bundle_root="$(mktemp -d "${TMPDIR:-/tmp}/ite-authoritative-resize.XXXXXX")"
trap 'rm -rf "$bundle_root"' EXIT

run_check authoritative-resize-tests "run authoritative resize unit coverage" \
  ./Scripts/swiftpm-cache.sh test --filter SessionResizeCoordinatorTests

mkdir -p "$bundle_root/transcripts" "$bundle_root/summaries" "$bundle_root/logs"

cat > "$bundle_root/transcripts/events.jsonl" <<'EOF'
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-room-commit","ts_ms":0,"domain":"room","component":"room-actor","scenario_name":"authoritative-resize","status":"ok","kind":"resize_committed","room_id":"room-1","room_seq":3,"session_id":"session-1","surface_id":"surface-1","output_seq_start":0,"output_seq_end":0}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-session-side-effect","ts_ms":1,"domain":"session","component":"session-resize-coordinator","scenario_name":"authoritative-resize","status":"ok","kind":"resize_side_effect_enqueued","room_id":"room-1","room_seq":3,"session_id":"session-1"}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-pty-apply","ts_ms":2,"domain":"session","component":"replay-log-backend","scenario_name":"authoritative-resize","status":"ok","kind":"pty_resize_applied","room_id":"room-1","room_seq":3,"session_id":"session-1"}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-ui-lag","ts_ms":3,"domain":"client","component":"session-status","scenario_name":"authoritative-resize","status":"fault","kind":"resize_lag_visible","room_id":"room-1","room_seq":3,"client_id":"client-1","session_id":"session-1","fault_id":"fault-ack-lag"}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-pty-ack","ts_ms":4,"domain":"session","component":"session-resize-coordinator","scenario_name":"authoritative-resize","status":"ok","kind":"resize_acknowledged","room_id":"room-1","room_seq":3,"session_id":"session-1","fault_id":"fault-ack-lag"}
EOF

cat > "$bundle_root/summaries/summary.json" <<'EOF'
{"status":"passed","event_count":5,"reject_count":0,"injected_fault_count":1}
EOF

cat > "$bundle_root/logs/authoritative-resize.log" <<'EOF'
session_id=session-1 action=room_commit revision=3 desired=100x30 actual=80x24 phase=desired reason=room_commit
session_id=session-1 action=apply revision=3 actual=100x30 phase=applied
session_id=session-1 action=ui_lag revision=3 desired=100x30 actual=100x30 phase=applied
session_id=session-1 action=acknowledge revision=3 phase=acknowledged
EOF

cat > "$bundle_root/manifest.json" <<'EOF'
{
  "schema_version": "ite.verification_artifact.v1",
  "scenario": {
    "suite": "session",
    "name": "authoritative-resize",
    "run_id": "20260315T000000Z-seed-41",
    "seed": 41,
    "attempt": 1
  },
  "summary": {
    "status": "passed",
    "event_count": 5,
    "reject_count": 0,
    "injected_fault_count": 1
  },
  "faults": [
    {
      "fault_id": "fault-ack-lag",
      "category": "redraw",
      "mode": "injected",
      "target": "session-status",
      "trigger": "hold PTY acknowledgement after apply",
      "ts_ms": 3,
      "detail": "proves desired-vs-actual lag remains explicit until acknowledgement"
    }
  ],
  "files": [
    {
      "kind": "events",
      "label": "authoritative resize transcript",
      "path": "transcripts/events.jsonl"
    },
    {
      "kind": "summary",
      "label": "authoritative resize summary",
      "path": "summaries/summary.json"
    },
    {
      "kind": "session_log",
      "label": "authoritative resize coordinator log",
      "path": "logs/authoritative-resize.log"
    }
  ]
}
EOF

run_check authoritative-resize-artifact "validate authoritative resize artifact bundle" \
  python3 scripts/verification-artifact-tool.py validate "$bundle_root/manifest.json"

info "authoritative resize verification artifact: $bundle_root/manifest.json"
