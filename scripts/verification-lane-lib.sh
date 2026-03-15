#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"

lane_begin() {
  LANE_NAME="$1"
  LANE_RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
  LANE_ROOT="artifacts/verification-lanes/$LANE_NAME/$LANE_RUN_ID"
  LANE_TRANSCRIPT="$LANE_ROOT/transcripts/checks.jsonl"
  LANE_SUMMARY="$LANE_ROOT/summaries/summary.json"
  LANE_STATUS="passed"
  LANE_TOTAL_STEPS=0
  LANE_PASSED_STEPS=0
  LANE_FAILED_STEPS=0

  mkdir -p "$LANE_ROOT/logs" "$(dirname "$LANE_TRANSCRIPT")" "$(dirname "$LANE_SUMMARY")"
  : > "$LANE_TRANSCRIPT"
  trap 'lane_finalize' EXIT
}

lane_run() {
  [ "$#" -ge 3 ] || fail "lane_run requires a step id, description, and command"

  step_id="$1"
  description="$2"
  shift 2

  LANE_TOTAL_STEPS=$((LANE_TOTAL_STEPS + 1))
  log_path="$LANE_ROOT/logs/$step_id.log"

  info "[$LANE_NAME/$step_id] $description"
  if "$@" >"$log_path" 2>&1; then
    status="passed"
    LANE_PASSED_STEPS=$((LANE_PASSED_STEPS + 1))
  else
    status="failed"
    LANE_STATUS="failed"
    LANE_FAILED_STEPS=$((LANE_FAILED_STEPS + 1))
  fi

  cat "$log_path"
  printf '{"step":"%s","status":"%s","log_path":"logs/%s.log"}\n' \
    "$step_id" "$status" "$step_id" >> "$LANE_TRANSCRIPT"

  [ "$status" = "passed" ] || return 1
}

lane_finalize() {
  cat > "$LANE_SUMMARY" <<EOF
{
  "lane": "$LANE_NAME",
  "run_id": "$LANE_RUN_ID",
  "status": "$LANE_STATUS",
  "total_steps": $LANE_TOTAL_STEPS,
  "passed_steps": $LANE_PASSED_STEPS,
  "failed_steps": $LANE_FAILED_STEPS
}
EOF

  info "$LANE_NAME lane artifacts: $LANE_ROOT"
}
