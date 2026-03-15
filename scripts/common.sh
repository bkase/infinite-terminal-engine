#!/bin/sh
set -eu

readonly REPO_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
readonly EXPECTED_ZIG_VERSION="0.15.2"
readonly EXPECTED_XCODE_VERSION="26.2"

info() {
  printf '==> %s\n' "$*"
}

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

run_check() {
  [ "$#" -ge 3 ] || fail "run_check requires a lane, description, and command"

  lane="$1"
  description="$2"
  shift 2

  info "[$lane] $description"
  if [ "${ITE_FAIL_CHECK:-}" = "$lane" ]; then
    fail "induced failure for lane '$lane' (ITE_FAIL_CHECK=$lane)"
  fi

  "$@" || fail "verification lane '$lane' failed"
}

run_optional_check() {
  [ "$#" -eq 3 ] || fail "run_optional_check requires a lane, description, and script path"

  lane="$1"
  description="$2"
  script_path="$3"

  if [ -x "$script_path" ]; then
    run_check "$lane" "$description" "$script_path"
  else
    info "[$lane] skipped ($script_path not present yet)"
  fi
}
