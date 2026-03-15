# Toolchain Policy

Pinned versions for this prototype:

- Zig `0.15.2`
- Xcode `26.2`
- Apple Swift `6.2.3`

`zig build doctor` is the authority for validating these expectations locally and in CI.

Commit gate:

- `.githooks/pre-commit`
- `scripts/verify-commit.sh`

Fast lane coverage:

- `doctor`: `zig build doctor`
- `formatting`: `zig build fmt`
- `engine-unit`: `zig build test-unit`
- `compositor-shader`: `zig build shader`
- `compositor-cpu`: `zig build test-integration-cpu`
- `compositor-gpu`: `zig build test-gpu`
- `host-shell`: `zig build host`
- `ghostty-wrapper`: `scripts/test-ghostty-wrapper.sh`
- `room`: `scripts/test-room.sh` when that bead lands
- `multiplayer`: `scripts/test-multiplayer.sh` when that bead lands

Failure injection:

- `scripts/verify-commit-failure.sh host-shell` forces the named lane to fail so the hook behavior stays testable.

Ghostty vendor pinning:

- `docs/ghostty-vendor.md` records the vendored Ghostty snapshot and the allowed wrapper boundary.

Shader staging contract:

- `zig build shader-air` writes `zig-out/shaders/rect_fill.air`
- `zig build shader-metallib` writes `zig-out/shaders/rect_fill.metallib`
- `zig build shader` stages `host/DemoApp/Resources/rect_fill.metallib`
- `zig build test-gpu` and `zig build host` depend on that staged metallib path

Demo gate:

- `scripts/verify-demo.sh`

Slow lane contents:

- Re-run `scripts/verify-commit.sh`
- `scripts/verify-packaging.sh`
- `Scripts/swiftpm-cache.sh build -c release`

Manual signoff:

- `docs/demo-signoff.md`

The repo-managed pre-commit hook runs `scripts/verify-commit.sh`, and CI uses the same script for the authoritative fast gate.
