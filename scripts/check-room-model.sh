#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root

artifact_root="${ITE_ARTIFACT_ROOT:-.build/verification-artifacts}"
run_id="$(date -u +%Y%m%dT%H%M%SZ)"
bundle_dir="$artifact_root/room/room-formal-model/$run_id"
mkdir -p "$bundle_dir/transcripts" "$bundle_dir/summaries" "$bundle_dir/failures"

log_path="$bundle_dir/failures/model.log"
status="passed"

if ! ./Scripts/swiftpm-cache.sh test --filter RoomFormalModelTests >"$log_path" 2>&1; then
  status="failed"
fi

cat >"$bundle_dir/transcripts/events.jsonl" <<EOF
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-room-model-start","ts_ms":0,"domain":"room","component":"room-formal-model","scenario_name":"room-formal-model","status":"ok","kind":"model_check_started","room_id":"room-1","room_seq":0}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-room-model-finish","ts_ms":1,"domain":"room","component":"room-formal-model","scenario_name":"room-formal-model","status":"ok","kind":"model_check_${status}","room_id":"room-1","room_seq":0}
{"schema_version":"ite.verification_artifact.v1","event_id":"evt-room-replay-equivalence","ts_ms":2,"domain":"room","component":"room-formal-model","scenario_name":"room-formal-model","status":"ok","kind":"snapshot_replay_equivalence_${status}","room_id":"room-1","room_seq":0}
EOF

cat >"$bundle_dir/summaries/summary.json" <<EOF
{
  "event_count": 3,
  "injected_fault_count": 0,
  "reject_count": 0,
  "status": "$status"
}
EOF

cat >"$bundle_dir/manifest.json" <<EOF
{
  "schema_version": "ite.verification_artifact.v1",
  "scenario": {
    "suite": "room",
    "name": "room-formal-model",
    "run_id": "$run_id"
  },
  "summary": {
    "status": "$status",
    "event_count": 3,
    "reject_count": 0,
    "injected_fault_count": 0
  },
  "faults": [],
  "files": [
    {
      "kind": "events",
      "label": "formal model transcript",
      "path": "transcripts/events.jsonl"
    },
    {
      "kind": "summary",
      "label": "formal model summary",
      "path": "summaries/summary.json"
    },
    {
      "kind": "failure_log",
      "label": "formal model raw output",
      "path": "failures/model.log"
    }
  ]
}
EOF

python3 ./scripts/verification-artifact-tool.py validate "$bundle_dir/manifest.json" >/dev/null

if [ "$status" != "passed" ]; then
  cat "$log_path" >&2
  fail "formal room model checks failed"
fi

info "formal room model artifacts written to $bundle_dir"
