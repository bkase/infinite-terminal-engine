#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root

zig fmt build.zig src tests

if [ -f Package.swift ]; then
  if swift format --help >/dev/null 2>&1; then
    swift format --recursive host Package.swift
  fi
fi
