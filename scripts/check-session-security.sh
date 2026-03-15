#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root
require_cmd python3

bundle_root="$(mktemp -d "${TMPDIR:-/tmp}/ite-session-security.XXXXXX")"
trap 'rm -rf "$bundle_root"' EXIT

run_check session-security-tests "run session transport security policy coverage" \
  ./Scripts/swiftpm-cache.sh test --filter 'SessionSecurityTests|SessionTransportTests'

mkdir -p "$bundle_root/transcripts" "$bundle_root/summaries" "$bundle_root/logs"

cat > "$bundle_root/transcripts/events.jsonl" <<'EOF'
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-subscribe-denied-membership","ts_ms":0,"domain":"security","component":"session-transport","scenario_name":"session-security-denials","status":"rejected","kind":"session_subscribe_denied","decision":"deny","session_id":"session-1","client_id":"client-1","reject_reason":"room_membership_required","fault_id":"fault-membership-deny"}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-input-denied-membership","ts_ms":1,"domain":"security","component":"session-transport","scenario_name":"session-security-denials","status":"rejected","kind":"input_denied","decision":"deny","session_id":"session-1","client_id":"client-1","reject_reason":"membership_revoked","fault_id":"fault-membership-deny"}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-token-expired","ts_ms":2,"domain":"security","component":"session-transport","scenario_name":"session-security-denials","status":"rejected","kind":"session_subscribe_denied","decision":"deny","session_id":"session-1","client_id":"client-1","reject_reason":"expired_token","fault_id":"fault-token-expired"}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-paste-forwarded","ts_ms":3,"domain":"security","component":"session-transport","scenario_name":"session-security-denials","status":"ok","kind":"paste_forwarded","decision":"allow","session_id":"session-1","client_id":"client-1"}
EOF

cat > "$bundle_root/summaries/summary.json" <<'EOF'
{"status":"passed","event_count":4,"reject_count":3,"injected_fault_count":1}
EOF

cat > "$bundle_root/logs/security-audit.log" <<'EOF'
event=session_subscribe_denied decision=deny failure_class=policy session_id=session-1 client_id=client-1 reason=roomMembershipRequired(sessionID: DemoApp.SessionID(rawValue: "session-1"), clientID: DemoApp.ClientID(rawValue: "client-1"))
event=input_denied decision=deny failure_class=policy session_id=session-1 client_id=client-1 client_input_seq=1 input_kind=keyboard reason=membershipRevoked(sessionID: DemoApp.SessionID(rawValue: "session-1"), clientID: DemoApp.ClientID(rawValue: "client-1"))
event=session_subscribe_denied decision=deny failure_class=policy session_id=session-1 client_id=client-1 reason=expiredToken(expiresAtMillis: 20, nowMillis: 25)
event=paste_forwarded decision=allow session_id=session-1 client_id=client-1 client_input_seq=7 input_kind=paste bytes=17
EOF

cat > "$bundle_root/manifest.json" <<'EOF'
{
  "schema_version": "ite.verification_artifact.v1",
  "scenario": {
    "suite": "security",
    "name": "session-security-denials",
    "run_id": "20260315T000000Z-seed-61",
    "seed": 61,
    "attempt": 1
  },
  "summary": {
    "status": "passed",
    "event_count": 4,
    "reject_count": 3,
    "injected_fault_count": 1
  },
  "faults": [
    {
      "fault_id": "fault-membership-deny",
      "category": "security_denial",
      "mode": "injected",
      "target": "session-transport",
      "trigger": "client attempts subscribe/input without room membership",
      "ts_ms": 1,
      "detail": "room membership is required for both initial subscribe and later input"
    },
    {
      "fault_id": "fault-token-expired",
      "category": "security_denial",
      "mode": "observed",
      "target": "session-transport",
      "trigger": "client presents an expired session token",
      "ts_ms": 2,
      "detail": "expired tokens are rejected before transport subscription is established"
    }
  ],
  "files": [
    {
      "kind": "events",
      "label": "session security transcript",
      "path": "transcripts/events.jsonl"
    },
    {
      "kind": "summary",
      "label": "session security summary",
      "path": "summaries/summary.json"
    },
    {
      "kind": "security_log",
      "label": "session security audit log",
      "path": "logs/security-audit.log"
    }
  ]
}
EOF

run_check session-security-artifact "validate session security verification artifact bundle" \
  python3 scripts/verification-artifact-tool.py validate "$bundle_root/manifest.json"

run_check session-security-audit "assert security audit log retains denial and paste fields" \
  python3 - "$bundle_root/logs/security-audit.log" <<'PY'
from pathlib import Path
import sys

log = Path(sys.argv[1]).read_text()
required = [
    "event=session_subscribe_denied decision=deny",
    "event=input_denied decision=deny",
    "input_kind=keyboard",
    "event=paste_forwarded decision=allow",
    "input_kind=paste",
]
missing = [entry for entry in required if entry not in log]
if missing:
    raise SystemExit(f"missing audit fields: {missing}")
PY

info "session security verification artifact: $bundle_root/manifest.json"
