#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root

env ITE_GHOSTTY_SELFTEST=1 Scripts/swiftpm-cache.sh run DemoApp
