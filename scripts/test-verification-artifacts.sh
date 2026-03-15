#!/bin/sh
set -eu

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

python3 ./scripts/verification-artifact-tool.py smoke "$tmpdir" >/dev/null
