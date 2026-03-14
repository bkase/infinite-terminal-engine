#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root

shader_src="src/shaders/rect_fill.metal"
air_out="zig-out/rect_fill.air"
metallib_out="zig-out/rect_fill.metallib"
staged_out="host/DemoApp/Resources/rect_fill.metallib"

[ -f "$shader_src" ] || fail "missing shader source: $shader_src"

mkdir -p zig-out host/DemoApp/Resources
xcrun metal -c "$shader_src" -o "$air_out"
xcrun metallib "$air_out" -o "$metallib_out"
cp "$metallib_out" "$staged_out"

printf 'staged metallib at %s\n' "$staged_out"
