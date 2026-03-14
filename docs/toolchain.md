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

Demo gate:

- `scripts/verify-demo.sh`

The repo-managed pre-commit hook runs `scripts/verify-commit.sh`.
