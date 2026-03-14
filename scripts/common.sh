#!/bin/sh
set -eu

readonly REPO_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
readonly EXPECTED_ZIG_VERSION="0.15.2"
readonly EXPECTED_XCODE_VERSION="26.2"

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

ensure_repo_root() {
  cd "$REPO_ROOT"
}
