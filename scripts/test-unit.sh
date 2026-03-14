#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root

zig test src/root.zig src/bridge/metal_bridge.m -lc -framework Foundation -framework Metal -framework QuartzCore -I src/bridge -I include
