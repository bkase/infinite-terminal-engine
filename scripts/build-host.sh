#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root

[ -f Package.swift ] || fail "missing Package.swift"
scripts/stage-engine-header.sh
Scripts/swiftpm-cache.sh test
Scripts/swiftpm-cache.sh build
