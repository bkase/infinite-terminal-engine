#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root

info "running slow demo/release verification lane"

run_check fast-lane "reuse the authoritative pre-commit verification lane" scripts/verify-commit.sh
run_check packaging "verify staged packaging artifacts" scripts/verify-packaging.sh
run_optional_check ghostty-wrapper "run Ghostty wrapper coverage" scripts/test-ghostty-wrapper.sh
run_check room-model "run formal room model and replay-equivalence checks" scripts/check-room-model.sh
run_check session-service "run session lifecycle and artifact checks" scripts/check-session-service.sh
run_check release-build "build the Swift host in release mode" Scripts/swiftpm-cache.sh build -c release

info "slow demo/release verification lane passed"
