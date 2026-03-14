#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root

zig test tests/gpu.zig -lc -framework Foundation -framework Metal -framework CoreGraphics
