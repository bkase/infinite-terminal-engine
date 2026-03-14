#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root

mkdir -p include zig-out/include zig-out/lib
zig build-lib src/root.zig \
  -femit-bin=zig-out/lib/libengine.a

cp include/engine.h zig-out/include/engine.h
