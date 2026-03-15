# Infinite Terminal Engine

Prototype for an Apple Silicon macOS infinite 2D canvas with:

- Zig engine and exported C ABI
- Native MSL shader pipeline
- Thin Objective-C Metal bridge
- SwiftUI/MetalKit host shell

Verification entrypoints:

- `scripts/install-hooks.sh`
- `scripts/verify-commit.sh`
- `scripts/verify-commit-failure.sh [lane]`
- `scripts/verify-demo.sh`
- `scripts/test-ghostty-wrapper.sh`
- `scripts/test-verification-artifacts.sh`
- `scripts/stage-engine-header.sh`
- `scripts/verify-packaging.sh`
- `zig build doctor`
- `zig build ci`

Fast vs slow lanes:

- Fast lane: `.githooks/pre-commit` runs `scripts/verify-commit.sh` and is the authoritative local/CI commit gate.
- Slow lane: `scripts/verify-demo.sh` reruns the fast lane, verifies packaging, and performs the release host build.
- Artifact contract: `scripts/test-verification-artifacts.sh` emits and validates the canonical retained bundle layout used by future room/session/client/compositor/security verification harnesses.
- Failure injection: `scripts/verify-commit-failure.sh host-shell` proves the hook rejects representative lane failures with specific output.
- Ghostty vendor contract: `docs/ghostty-vendor.md` records the pinned snapshot and the wrapper-only boundary.
- Collaborative render profiles: `host/DemoApp/Resources/RenderProfiles.json` pins the PragmataPro geometry contract used by the host.
- Render profile behavior: `docs/render-profiles.md` documents the deterministic sizing rules and failure mode.

Run locally:

- `swift run DemoApp`
