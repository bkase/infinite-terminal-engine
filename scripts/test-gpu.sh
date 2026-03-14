#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root

zig test src/gpu.zig src/bridge/metal_bridge.m -lc -framework Foundation -framework Metal -framework CoreGraphics -framework QuartzCore -I src/bridge -I include
