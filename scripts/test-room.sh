#!/bin/sh
set -eu

./Scripts/swiftpm-cache.sh test --filter Room
./scripts/test-verification-artifacts.sh
