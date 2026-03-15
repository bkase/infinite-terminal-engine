#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root

lane="${1:-host-shell}"

info "expecting scripts/verify-commit.sh to fail in lane '$lane'"
if ITE_FAIL_CHECK="$lane" scripts/verify-commit.sh; then
  fail "verify-commit unexpectedly passed with ITE_FAIL_CHECK=$lane"
fi

info "failure injection behaved as expected for lane '$lane'"
