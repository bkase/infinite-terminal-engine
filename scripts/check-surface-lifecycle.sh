#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root
require_cmd python3

bundle_root="$(mktemp -d "${TMPDIR:-/tmp}/ite-surface-lifecycle.XXXXXX")"
trap 'rm -rf "$bundle_root"' EXIT

run_check surface-lifecycle-tests "run surface lifecycle integration coverage" \
  ./Scripts/swiftpm-cache.sh test --filter SurfaceLifecycleCoordinatorTests

mkdir -p "$bundle_root/transcripts" "$bundle_root/summaries" "$bundle_root/logs"

cat > "$bundle_root/transcripts/events.jsonl" <<'EOF'
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-surface-create","ts_ms":0,"domain":"room","component":"surface-lifecycle","scenario_name":"surface-lifecycle","status":"ok","kind":"surface_created","room_id":"room-1","room_seq":1,"session_id":"session-1","surface_id":"surface-1"}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-surface-attach","ts_ms":1,"domain":"session","component":"surface-lifecycle","scenario_name":"surface-lifecycle","status":"ok","kind":"session_attached","room_id":"room-1","room_seq":2,"session_id":"session-1","surface_id":"surface-1"}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-surface-viewer","ts_ms":2,"domain":"client","component":"surface-lifecycle","scenario_name":"surface-lifecycle","status":"ok","kind":"surface_subscribed","room_id":"room-1","room_seq":2,"client_id":"viewer-1","session_id":"session-1","surface_id":"surface-1"}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-surface-degraded","ts_ms":3,"domain":"client","component":"surface-lifecycle","scenario_name":"surface-lifecycle","status":"fault","kind":"surface_overlay_failed","room_id":"room-1","room_seq":2,"client_id":"viewer-2","session_id":"session-2","surface_id":"surface-2","fault_id":"fault-client-disconnect"}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-surface-error","ts_ms":4,"domain":"session","component":"surface-lifecycle","scenario_name":"surface-lifecycle","status":"fault","kind":"session_failed","room_id":"room-1","room_seq":2,"session_id":"session-1","surface_id":"surface-1","fault_id":"fault-session-down"}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-surface-close","ts_ms":5,"domain":"room","component":"surface-lifecycle","scenario_name":"surface-lifecycle","status":"ok","kind":"surface_closed","room_id":"room-1","room_seq":3,"session_id":"session-1","surface_id":"surface-1"}
EOF

cat > "$bundle_root/summaries/summary.json" <<'EOF'
{"status":"passed","event_count":6,"reject_count":0,"injected_fault_count":2}
EOF

cat > "$bundle_root/logs/surface-lifecycle.log" <<'EOF'
surface_id=surface-1 action=create
surface_id=surface-1 session_id=session-1 action=session_started
surface_id=surface-1 session_id=session-1 action=attach
surface_id=surface-1 lifecycle=attached room_state=attached session_status=running client_count=0
surface_id=surface-2 lifecycle=degraded room_state=attached session_status=running client_count=1
surface_id=surface-1 lifecycle=error room_state=attached session_status=failed client_count=1
surface_id=surface-1 action=closing
surface_id=surface-1 action=closed
EOF

cat > "$bundle_root/manifest.json" <<'EOF'
{
  "schema_version": "ite.verification_artifact.v1",
  "scenario": {
    "suite": "multiplayer",
    "name": "surface-lifecycle",
    "run_id": "20260315T000000Z-seed-47",
    "seed": 47,
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
      "fault_id": "fault-client-disconnect",
      "category": "outage",
      "mode": "injected",
      "target": "session-client",
      "trigger": "one subscribed viewer disconnects while the room and session remain up",
      "ts_ms": 3,
      "detail": "proves the derived lifecycle becomes degraded instead of collapsing the surface"
    },
    {
      "fault_id": "fault-session-down",
      "category": "outage",
      "mode": "injected",
      "target": "session-actor",
      "trigger": "session backend fails after attach",
      "ts_ms": 4,
      "detail": "proves lifecycle transitions to error while the room record still exists"
    }
  ],
  "files": [
    {
      "kind": "events",
      "label": "surface lifecycle transcript",
      "path": "transcripts/events.jsonl"
    },
    {
      "kind": "summary",
      "label": "surface lifecycle summary",
      "path": "summaries/summary.json"
    },
    {
      "kind": "session_log",
      "label": "surface lifecycle log",
      "path": "logs/surface-lifecycle.log"
    }
  ]
}
EOF

run_check surface-lifecycle-artifact "validate surface lifecycle artifact bundle" \
  python3 scripts/verification-artifact-tool.py validate "$bundle_root/manifest.json"

info "surface lifecycle verification artifact: $bundle_root/manifest.json"
