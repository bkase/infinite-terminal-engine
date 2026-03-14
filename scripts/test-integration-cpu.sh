#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root

mkdir -p zig-out/include zig-out/lib
zig build-lib src/root.zig \
  -femit-bin=zig-out/lib/libengine.a

cp include/engine.h zig-out/include/engine.h
cc ctests/header_smoke.c zig-out/lib/libengine.a -Izig-out/include -o zig-out/header_smoke
./zig-out/header_smoke
zig test tests/integration.zig -Izig-out/include -Lzig-out/lib -lengine
