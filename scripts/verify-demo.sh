#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root

scripts/verify-commit.sh
scripts/verify-packaging.sh
Scripts/swiftpm-cache.sh build -c release
