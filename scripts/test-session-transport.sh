#!/bin/sh
set -eu

exec ./Scripts/swiftpm-cache.sh test --filter SessionTransportTests
