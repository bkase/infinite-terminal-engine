#!/bin/sh
set -eu

exec ./scripts/swiftpm-cache.sh test --filter RoomSchemaTests
