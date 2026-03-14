#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root

require_cmd zig
require_cmd xcodebuild
require_cmd xcrun
require_cmd swift
require_cmd git

zig_version="$(zig version)"
[ "$zig_version" = "$EXPECTED_ZIG_VERSION" ] || fail "expected Zig $EXPECTED_ZIG_VERSION, found $zig_version"

xcode_version="$(xcodebuild -version | awk 'NR==1 { print $2 }')"
[ "$xcode_version" = "$EXPECTED_XCODE_VERSION" ] || fail "expected Xcode $EXPECTED_XCODE_VERSION, found $xcode_version"

xcrun metal -v >/dev/null 2>&1 || fail "xcrun metal is unavailable"
xcrun metallib -help >/dev/null 2>&1 || fail "xcrun metallib is unavailable"

printf 'doctor ok: Zig %s, Xcode %s\n' "$zig_version" "$xcode_version"
