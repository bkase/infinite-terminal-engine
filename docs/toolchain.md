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

Shader staging contract:

- `build.zig` owns the named shader steps: `shader-air`, `shader-metallib`, and `shader`
- `zig build shader-air` installs `zig-out/shaders/rect_fill.air`
- `zig build shader-metallib` installs `zig-out/shaders/rect_fill.metallib`
- `zig build shader` stages `host/DemoApp/Resources/rect_fill.metallib`
- `zig build test-gpu` and `zig build host` depend on the staged metallib path above

Demo gate:

- `scripts/verify-demo.sh`

The repo-managed pre-commit hook runs `scripts/verify-commit.sh`.
