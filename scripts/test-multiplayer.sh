#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root
require_cmd python3

bundle_root="${ITE_MULTIPLAYER_ARTIFACT_ROOT:-$(mktemp -d "${TMPDIR:-/tmp}/ite-multiplayer.XXXXXX")}"
export ITE_MULTIPLAYER_ARTIFACT_ROOT="$bundle_root"

run_check multiplayer-tests "run deterministic multiplayer acceptance coverage" \
  ./Scripts/swiftpm-cache.sh test --filter MultiplayerAcceptanceTests

set -- "$bundle_root"/multiplayer/*/*/manifest.json
[ -e "$1" ] || fail "multiplayer acceptance tests did not emit any manifests under $bundle_root"

for manifest in "$@"; do
  run_check multiplayer-artifact "validate $(basename "$(dirname "$manifest")")" \
    python3 scripts/verification-artifact-tool.py validate "$manifest"
done

info "multiplayer acceptance artifacts: $bundle_root"
