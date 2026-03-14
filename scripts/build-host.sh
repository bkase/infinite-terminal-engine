#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root

[ -f Package.swift ] || fail "missing Package.swift"
Scripts/swiftpm-cache.sh build
