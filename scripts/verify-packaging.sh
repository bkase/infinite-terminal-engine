#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root

[ -f host/DemoApp/Resources/rect_fill.metallib ] || fail "missing staged metallib"
[ -f host/DemoApp/Resources/libengine.dylib ] || fail "missing staged engine dylib"
[ -f .build/apus-release/arm64-apple-macosx/debug/DemoApp ] || true

printf 'packaging ok: staged metallib and engine dylib present\n'
