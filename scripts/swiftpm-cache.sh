#!/bin/sh
set -eu

if [ "$#" -lt 1 ]; then
  printf 'usage: %s <swift-subcommand> [args...]\n' "$0" >&2
  exit 1
fi

subcommand="$1"
shift

cache_root=".build/apus-debug"
if [ "$subcommand" = "build" ] && [ "${1:-}" = "-c" ] && [ "${2:-}" = "release" ]; then
  cache_root=".build/apus-release"
fi

exec swift \
  "$subcommand" \
  --scratch-path "$cache_root" \
  "$@"
