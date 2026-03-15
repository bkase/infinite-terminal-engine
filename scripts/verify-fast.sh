#!/bin/sh
set -eu

. "$(dirname "$0")/verification-lane-lib.sh"
ensure_repo_root

info "running fast verification lane"
lane_begin fast

lane_run doctor "validate pinned local toolchain" scripts/doctor.sh
lane_run formatting "check repository formatting" scripts/fmt.sh
lane_run compositor-shader "stage shader artifacts used by host and GPU tests" scripts/build-shader.sh stage
lane_run compositor-cpu "run CPU integration + ABI coverage (includes unit tests)" scripts/test-integration-cpu.sh
lane_run compositor-gpu "run headless GPU smoke coverage (includes unit tests)" scripts/test-gpu.sh
lane_run host-shell "build and test the host shell path" scripts/build-host.sh
lane_run multiplayer "run multiplayer lifecycle and reconnect checks" scripts/test-multiplayer.sh

info "fast verification lane passed"
