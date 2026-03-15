#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root
require_cmd python3

bundle_root="${ITE_OBSERVABILITY_ARTIFACT_ROOT:-$(mktemp -d "${TMPDIR:-/tmp}/ite-observability.XXXXXX")}"
export ITE_OBSERVABILITY_ARTIFACT_ROOT="$bundle_root"

run_check observability-tests "run observability smoke coverage" \
  ./Scripts/swiftpm-cache.sh test --filter ObservabilityTests

manifest="$bundle_root/observability/observability-smoke/20260315T000000Z-seed-301/manifest.json"
[ -f "$manifest" ] || fail "observability smoke did not emit $manifest"

run_check observability-artifact "validate observability artifact bundle" \
  python3 scripts/verification-artifact-tool.py validate "$manifest"

info "observability artifact: $manifest"
