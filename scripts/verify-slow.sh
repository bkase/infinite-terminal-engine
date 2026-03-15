#!/bin/sh
set -eu

. "$(dirname "$0")/verification-lane-lib.sh"
ensure_repo_root

info "running slow verification lane"
lane_begin slow

lane_run fast-lane "reuse the authoritative fast verification lane" scripts/verify-fast.sh
lane_run observability "run observability artifact smoke" scripts/check-observability.sh
lane_run room-model "run formal room model and replay-equivalence checks" scripts/check-room-model.sh
lane_run session-service "run session lifecycle and artifact checks" scripts/check-session-service.sh
lane_run step2-stress "run bounded N=50 compositor stress coverage" scripts/test-step2-stress.sh
lane_run multiplayer "run multiplayer lifecycle and reconnect checks" scripts/test-multiplayer.sh
lane_run replay "replay retained room/session artifacts from multiplayer verification" scripts/test-replay-artifacts.sh
lane_run security "run session transport security denial coverage" scripts/check-session-security.sh
lane_run packaging "verify staged packaging artifacts" scripts/verify-packaging.sh
lane_run release-build "build the Swift host in release mode" Scripts/swiftpm-cache.sh build -c release

info "slow verification lane passed"
