#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root

info "running fast verification lane"

run_check doctor "validate pinned local toolchain" scripts/doctor.sh
run_check formatting "check repository formatting" scripts/fmt.sh
run_check compositor-shader "stage shader artifacts used by host and GPU tests" scripts/build-shader.sh stage
run_check compositor-cpu "run CPU integration + ABI coverage (includes unit tests)" scripts/test-integration-cpu.sh
run_check compositor-gpu "run headless GPU smoke coverage (includes unit tests)" scripts/test-gpu.sh
run_check host-shell "build and test the host shell path" scripts/build-host.sh
run_optional_check multiplayer "run multiplayer lifecycle and reconnect checks once available" scripts/test-multiplayer.sh

info "fast verification lane passed"
