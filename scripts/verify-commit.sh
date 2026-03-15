#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root

info "running fast verification lane"

run_check doctor "validate pinned local toolchain" zig build doctor
run_check formatting "check repository formatting" zig build fmt
run_check engine-unit "run Zig unit tests" zig build test-unit
run_check compositor-shader "stage shader artifacts used by host and GPU tests" zig build shader
run_check compositor-cpu "run CPU integration coverage for the current renderer path" zig build test-integration-cpu
run_check compositor-gpu "run headless GPU smoke coverage for the compositor path" zig build test-gpu
run_check host-shell "build and test the host shell path" zig build host
run_optional_check ghostty-wrapper "run Ghostty wrapper coverage once the adapter lands" scripts/test-ghostty-wrapper.sh
run_optional_check room "run room sequencing and persistence checks once available" scripts/test-room.sh
run_optional_check multiplayer "run multiplayer lifecycle and reconnect checks once available" scripts/test-multiplayer.sh

info "fast verification lane passed"
