#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root

mode="${1:-stage}"
shader_src="src/shaders/rect_fill.metal"
shader_dir="zig-out/shaders"
air_out="$shader_dir/rect_fill.air"
metallib_out="$shader_dir/rect_fill.metallib"
staged_out="host/DemoApp/Resources/rect_fill.metallib"

[ -f "$shader_src" ] || fail "missing shader source: $shader_src"

mkdir -p "$shader_dir" host/DemoApp/Resources

case "$mode" in
  air)
    xcrun metal -c "$shader_src" -o "$air_out"
    printf 'built AIR at %s\n' "$air_out"
    ;;
  metallib)
    xcrun metal -c "$shader_src" -o "$air_out"
    xcrun metallib "$air_out" -o "$metallib_out"
    printf 'built metallib at %s\n' "$metallib_out"
    ;;
  stage)
    xcrun metal -c "$shader_src" -o "$air_out"
    xcrun metallib "$air_out" -o "$metallib_out"
    cp "$metallib_out" "$staged_out"
    printf 'staged metallib at %s\n' "$staged_out"
    ;;
  *)
    fail "unknown shader build mode: $mode"
    ;;
esac
