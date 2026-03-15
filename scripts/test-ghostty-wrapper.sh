#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"
ensure_repo_root

info "building pinned Ghostty VT library"
(
  cd ghostty
  zig build lib-vt
)

info "checking for non-wrapper Ghostty usage"
matches="$(
  rg -n --no-heading '(#include[[:space:]]*[<"]ghostty/|[^[:alnum:]_])ghostty_[[:alnum:]_]+' include src host tests ctests \
    --glob '!include/ite_ghostty_wrapper.h' \
    --glob '!src/vendor/ghostty_wrapper.c' \
    --glob '!host/DemoApp/GhosttySurfaceAdapter.swift' \
    --glob '!ctests/ghostty_wrapper_smoke.c' || true
)"
if [ -n "$matches" ]; then
  printf '%s\n' "$matches" >&2
  fail "Ghostty API usage must stay inside include/ite_ghostty_wrapper.h, src/vendor/ghostty_wrapper.c, or the sanctioned host adapter"
fi

mkdir -p zig-out
cc ctests/ghostty_wrapper_smoke.c src/vendor/ghostty_wrapper.c \
  -Iinclude \
  -Ighostty/zig-out/include \
  -Lghostty/zig-out/lib \
  -lghostty-vt \
  -Wl,-rpath,"$REPO_ROOT/ghostty/zig-out/lib" \
  -o zig-out/ghostty_wrapper_smoke

./zig-out/ghostty_wrapper_smoke
