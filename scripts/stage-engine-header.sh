#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root

mkdir -p include zig-out/include zig-out/lib
cp include/engine.h zig-out/include/engine.h
zig build-lib \
  src/root.zig \
  src/bridge/metal_bridge.m \
  -dynamic \
  -lc \
  -framework Foundation \
  -framework Metal \
  -framework QuartzCore \
  -femit-bin=zig-out/lib/libengine.dylib
