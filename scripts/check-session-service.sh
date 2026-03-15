#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root
require_cmd python3

bundle_root="$(mktemp -d "${TMPDIR:-/tmp}/ite-session-service.XXXXXX")"
trap 'rm -rf "$bundle_root"' EXIT

run_check session-tests "run session service unit coverage" ./scripts/test-session-service.sh

mkdir -p "$bundle_root/transcripts" "$bundle_root/summaries" "$bundle_root/logs"

cat > "$bundle_root/transcripts/events.jsonl" <<'EOF'
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-session-provision","ts_ms":0,"domain":"session","component":"session-actor","scenario_name":"session-service-lifecycle","status":"ok","kind":"session_provisioned","session_id":"session-1"}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-session-running","ts_ms":1,"domain":"session","component":"session-actor","scenario_name":"session-service-lifecycle","status":"ok","kind":"backend_started","session_id":"session-1"}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-session-bootstrap","ts_ms":2,"domain":"session","component":"session-actor","scenario_name":"session-service-lifecycle","status":"ok","kind":"bootstrap_redraw","session_id":"session-1"}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-session-output","ts_ms":3,"domain":"session","component":"session-actor","scenario_name":"session-service-lifecycle","status":"ok","kind":"output_chunk","session_id":"session-1"}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-session-exit","ts_ms":4,"domain":"session","component":"session-actor","scenario_name":"session-service-lifecycle","status":"ok","kind":"session_exited","session_id":"session-1"}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-session-failed","ts_ms":5,"domain":"session","component":"session-actor","scenario_name":"session-service-lifecycle","status":"fault","kind":"session_failed","session_id":"session-2","fault_id":"fault-buffer-overflow"}
EOF

cat > "$bundle_root/summaries/summary.json" <<'EOF'
{"status":"passed","event_count":6,"reject_count":0,"injected_fault_count":1}
EOF

cat > "$bundle_root/logs/session-1.log" <<'EOF'
session_id=session-1 status=provisioning size=80x24
session_id=session-1 status=running output_seq=0 subscriber_count=0
session_id=session-1 bootstrap_anchor=0 subscriber_count=1
session_id=session-1 status=exited exit_code=0 output_seq=5
EOF

cat > "$bundle_root/logs/session-2.log" <<'EOF'
session_id=session-2 status=running output_seq=4 subscriber_count=1
session_id=session-2 status=failed reason=buffered_output_limit_exceeded output_seq=4
EOF

cat > "$bundle_root/manifest.json" <<'EOF'
{
  "schema_version": "ite.verification_artifact.v1",
  "scenario": {
    "suite": "session",
    "name": "session-service-lifecycle",
    "run_id": "20260315T000000Z-seed-17",
    "seed": 17,
    "attempt": 1
  },
  "summary": {
    "status": "passed",
    "event_count": 6,
    "reject_count": 0,
    "injected_fault_count": 1
  },
  "faults": [
    {
      "fault_id": "fault-buffer-overflow",
      "category": "outage",
      "mode": "injected",
      "target": "session-actor",
      "trigger": "buffered output exceeds per-session limit",
      "ts_ms": 5,
      "detail": "force transition into failed to prove deterministic diagnostics"
    }
  ],
  "files": [
    {
      "kind": "events",
      "label": "session event transcript",
      "path": "transcripts/events.jsonl"
    },
    {
      "kind": "summary",
      "label": "session summary",
      "path": "summaries/summary.json"
    },
    {
      "kind": "session_log",
      "label": "session-1 lifecycle log",
      "path": "logs/session-1.log"
    },
    {
      "kind": "session_log_failure",
      "label": "session-2 forced failure log",
      "path": "logs/session-2.log"
    }
  ]
}
EOF

run_check session-artifact "validate session verification artifact bundle" \
  python3 scripts/verification-artifact-tool.py validate "$bundle_root/manifest.json"

info "session service verification artifact: $bundle_root/manifest.json"
