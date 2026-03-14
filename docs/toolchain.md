# Toolchain Policy

Pinned versions for this prototype:

- Zig `0.15.2`
- Xcode `26.2`
- Apple Swift `6.2.3`

`zig build doctor` is the authority for validating these expectations locally and in CI.

Commit gate:

- `zig build doctor`
- `zig build fmt`
- `zig build test-unit`
- `zig build shader`
- `zig build test-integration-cpu`
- `zig build test-gpu`
- `zig build host`
- `scripts/verify-packaging.sh`

Shader staging contract:

- `zig build shader-air` writes `zig-out/shaders/rect_fill.air`
- `zig build shader-metallib` writes `zig-out/shaders/rect_fill.metallib`
- `zig build shader` stages `host/DemoApp/Resources/rect_fill.metallib`
- `zig build test-gpu` and `zig build host` depend on that staged metallib path

Demo gate:

- `scripts/verify-demo.sh`

Manual signoff:

- `docs/demo-signoff.md`

The repo-managed pre-commit hook runs `scripts/verify-commit.sh`.
