#!/bin/sh
set -eu

. "$(dirname "$0")/verification-lane-lib.sh"
ensure_repo_root

iterations="${ITE_SOAK_ITERATIONS:-5}"

info "running bounded soak verification lane"
lane_begin soak

lane_run fast-lane "reuse the authoritative fast verification lane" scripts/verify-fast.sh

i=1
while [ "$i" -le "$iterations" ]; do
  lane_run "session-churn-$i" "repeat multiplayer reconnect churn iteration $i/$iterations" \
    Scripts/swiftpm-cache.sh test --filter MultiplayerAcceptanceTests
  i=$((i + 1))
done

lane_run replay "replay retained artifacts after soak churn" scripts/test-replay-artifacts.sh
lane_run security "recheck session transport denial and paste audit coverage" scripts/check-session-security.sh

info "bounded soak verification lane passed"
