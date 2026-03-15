#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root
require_cmd python3

bundle_root="$(mktemp -d "${TMPDIR:-/tmp}/ite-replay-artifacts.XXXXXX")"
trap 'rm -rf "$bundle_root"' EXIT

run_check replay-source "generate multiplayer reconnect artifacts" \
  env ITE_MULTIPLAYER_ARTIFACT_ROOT="$bundle_root" ./scripts/test-multiplayer.sh

room_manifest="$bundle_root/multiplayer/room-reconnect-live-session/20260315T000000Z-seed-203/manifest.json"
session_manifest="$bundle_root/multiplayer/session-reconnect-replay/20260315T000000Z-seed-204/manifest.json"

[ -f "$room_manifest" ] || fail "missing room replay manifest: $room_manifest"
[ -f "$session_manifest" ] || fail "missing session replay manifest: $session_manifest"

run_check replay-room "replay retained room snapshot + journal" \
  python3 scripts/replay-artifact-tool.py room "$room_manifest" --check

run_check replay-session "replay retained session bootstrap + output" \
  python3 scripts/replay-artifact-tool.py session "$session_manifest" --check

info "replay artifact verification passed: $bundle_root"
