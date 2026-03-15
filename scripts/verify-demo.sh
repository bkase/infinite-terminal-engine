#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root

info "running demo verification lane"

run_check slow-lane "run the canonical slow verification lane" scripts/verify-slow.sh
run_check startup "run the real DemoApp startup self-test" scripts/test-ghostty-surface-adapter.sh

info "manual signoff checklist: docs/demo-signoff.md"
info "demo verification lane passed"
