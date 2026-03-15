# Ghostty Vendor Contract

Pinned snapshot:

- `ghostty/` commit `332b2aefc6e72d363aa93ab6ecfc86eeeeb5ed28`

Boundary rules:

- `include/ite_ghostty_wrapper.h` is the only supported Ghostty-facing header for the product.
- `src/vendor/ghostty_wrapper.c` is the only product source file allowed to include Ghostty headers or call `ghostty_*` symbols directly.
- `host/DemoApp/GhosttySurfaceAdapter.swift` is the only sanctioned non-wrapper embed point for the host-side surface proof.
- `scripts/test-ghostty-wrapper.sh` enforces that boundary with a repo scan and a link-time smoke test.

Current compatibility surface:

- `ghostty_key_encoder_new`
- `ghostty_key_encoder_free`
- `ghostty_key_encoder_setopt`
- `ghostty_key_encoder_encode`
- `ghostty_key_event_new`
- `ghostty_key_event_free`
- `ghostty_key_event_set_action`
- `ghostty_key_event_set_key`
- `ghostty_key_event_set_mods`
- `ghostty_key_event_set_consumed_mods`
- `ghostty_key_event_set_composing`
- `ghostty_key_event_set_utf8`
- `ghostty_key_event_set_unshifted_codepoint`
- `ghostty_paste_is_safe`

When wrapper edits are required:

- The pinned snapshot commit changes.
- Any symbol above is removed, renamed, or changes semantics.
- The wrapper needs new input-translation, clipboard, resize, or render hooks for later Ghostty embedding beads.

Failure modes:

- If the vendored `libghostty-vt` no longer exports the wrapper's symbols, `scripts/test-ghostty-wrapper.sh` fails at compile or link time.
- If any non-wrapper code starts using Ghostty headers or `ghostty_*` symbols directly, the same script fails the boundary scan.

Embedded surface note:

- The current host-side `GhosttySurfaceAdapter` uses Ghostty's AppKit embed path and exports the rendered front buffer through the host view's `IOSurface`-backed layer contents.
- Direct C-API render-to-app-managed-texture is not exposed by the pinned Ghostty embedded surface boundary, so the adapter's documented fallback is to create an `MTLTexture` view over that `IOSurface`.
- `scripts/test-ghostty-surface-adapter.sh` exercises the supported contract with a loopback harness: init, text injection, front-texture availability, resize, continued rendering, and shutdown.
