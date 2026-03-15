#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root

[ -f Package.swift ] || fail "missing Package.swift"
scripts/stage-engine-header.sh
Scripts/swiftpm-cache.sh test
scripts/test-ghostty-surface-adapter.sh
scripts/test-verification-artifacts.sh
