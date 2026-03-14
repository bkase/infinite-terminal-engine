#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root

scripts/stage-engine-header.sh
cc ctests/header_smoke.c -Izig-out/include -Lzig-out/lib -lengine -Wl,-rpath,"$REPO_ROOT/zig-out/lib" -o zig-out/header_smoke
./zig-out/header_smoke
zig test src/integration.zig
