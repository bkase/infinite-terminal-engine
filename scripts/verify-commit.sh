#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root

zig build doctor
zig build fmt
zig build test-unit
zig build shader
zig build test-integration-cpu
zig build test-gpu
zig build host
