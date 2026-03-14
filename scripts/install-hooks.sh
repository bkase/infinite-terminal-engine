#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root

git config core.hooksPath .githooks
chmod +x .githooks/pre-commit

printf 'installed repo-managed git hooks\n'
