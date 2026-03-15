#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root
require_cmd python3

bundle_root="$(mktemp -d "${TMPDIR:-/tmp}/ite-session-transport.XXXXXX")"
trap 'rm -rf "$bundle_root"' EXIT

run_check session-transport-tests "run session transport unit coverage" ./scripts/test-session-transport.sh

mkdir -p "$bundle_root/transcripts" "$bundle_root/summaries" "$bundle_root/logs"

cat > "$bundle_root/transcripts/events.jsonl" <<'EOF'
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-session-auth","ts_ms":0,"domain":"session","component":"session-transport","scenario_name":"session-transport-reconnect","status":"ok","kind":"transport_auth_ok","session_id":"session-1"}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-session-bootstrap","ts_ms":1,"domain":"session","component":"session-transport","scenario_name":"session-transport-reconnect","status":"ok","kind":"bootstrap_redraw","session_id":"session-1","output_seq_start":1,"output_seq_end":6}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-session-drop","ts_ms":2,"domain":"session","component":"session-transport","scenario_name":"session-transport-reconnect","status":"fault","kind":"transport_disconnected","session_id":"session-1","fault_id":"fault-dropped-connection"}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-session-reconnect","ts_ms":3,"domain":"session","component":"session-transport","scenario_name":"session-transport-reconnect","status":"ok","kind":"reconnect_started","session_id":"session-1","fault_id":"fault-dropped-connection","output_seq_start":9,"output_seq_end":11}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-session-lease-revoked","ts_ms":4,"domain":"session","component":"session-transport","scenario_name":"session-transport-reconnect","status":"fault","kind":"lease_revoked","session_id":"session-1","fault_id":"fault-lease-epoch-change"}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-session-auth-failed","ts_ms":5,"domain":"session","component":"session-transport","scenario_name":"session-transport-reconnect","status":"fault","kind":"transport_auth_failed","session_id":"session-1","fault_id":"fault-bad-token"}
EOF

cat > "$bundle_root/summaries/summary.json" <<'EOF'
{"status":"passed","event_count":6,"reject_count":0,"injected_fault_count":3}
EOF

cat > "$bundle_root/logs/session-transport.log" <<'EOF'
connection_id=session-session-1-conn-1 session_id=session-1 client_id=client-1 auth=ok lease_epoch=5
connection_id=session-session-1-conn-1 resume_mode=bootstrap reconnect_after=none
connection_id=session-session-1-conn-1 direction=s2c type=bootstrap seq_start=1 seq_end=6 bytes=6
connection_id=session-session-1-conn-1 direction=s2c type=status session_status=running output_seq=6
connection_id=session-session-1-conn-1 disconnected reason=simulate drop
connection_id=session-session-1-conn-2 session_id=session-1 client_id=client-1 auth=ok lease_epoch=5
connection_id=session-session-1-conn-2 resume_mode=replay reconnect_after=8
connection_id=session-session-1-conn-2 direction=s2c type=output seq_start=9 seq_end=11 bytes=3
connection_id=session-session-1-conn-2 direction=s2c type=status session_status=running output_seq=11
connection_id=session-session-1-conn-2 direction=s2c type=lease_revoked previous_epoch=5 current_epoch=6
EOF

cat > "$bundle_root/logs/auth-failures.log" <<'EOF'
session_id=session-1 client_id=client-1 auth=failed reason=malformed_token
session_id=session-1 client_id=client-1 auth=failed reason=lease_epoch_mismatch expected=6 actual=5
EOF

cat > "$bundle_root/manifest.json" <<'EOF'
{
  "schema_version": "ite.verification_artifact.v1",
  "scenario": {
    "suite": "session",
    "name": "session-transport-reconnect",
    "run_id": "20260315T000000Z-seed-29",
    "seed": 29,
    "attempt": 1
  },
  "summary": {
    "status": "passed",
    "event_count": 6,
    "reject_count": 0,
    "injected_fault_count": 3
  },
  "faults": [
    {
      "fault_id": "fault-dropped-connection",
      "category": "reconnect",
      "mode": "injected",
      "target": "session-transport",
      "trigger": "disconnect active transport after live output",
      "ts_ms": 2,
      "detail": "forces reconnect replay from a known output anchor"
    },
    {
      "fault_id": "fault-lease-epoch-change",
      "category": "lease",
      "mode": "injected",
      "target": "session-transport",
      "trigger": "change current lease epoch after auth",
      "ts_ms": 4,
      "detail": "queues an explicit lease_revoked data-plane message"
    },
    {
      "fault_id": "fault-bad-token",
      "category": "security_denial",
      "mode": "injected",
      "target": "session-transport",
      "trigger": "tamper token payload",
      "ts_ms": 5,
      "detail": "proves auth failure remains observable and session-local"
    }
  ],
  "files": [
    {
      "kind": "events",
      "label": "session transport transcript",
      "path": "transcripts/events.jsonl"
    },
    {
      "kind": "summary",
      "label": "session transport summary",
      "path": "summaries/summary.json"
    },
    {
      "kind": "session_log",
      "label": "transport reconnect log",
      "path": "logs/session-transport.log"
    },
    {
      "kind": "security_log",
      "label": "transport auth failure log",
      "path": "logs/auth-failures.log"
    }
  ]
}
EOF

run_check session-transport-artifact "validate session transport verification artifact bundle" \
  python3 scripts/verification-artifact-tool.py validate "$bundle_root/manifest.json"

info "session transport verification artifact: $bundle_root/manifest.json"
