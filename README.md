# Infinite Terminal Engine

Prototype for an Apple Silicon macOS infinite 2D canvas with:

- Zig engine and exported C ABI
- Native MSL shader pipeline
- Thin Objective-C Metal bridge
- SwiftUI/MetalKit host shell

Verification entrypoints:

- `scripts/install-hooks.sh`
- `scripts/verify-commit.sh`
- `scripts/verify-fast.sh`
- `scripts/verify-slow.sh`
- `scripts/verify-soak.sh`
- `scripts/verify-commit-failure.sh [lane]`
- `scripts/verify-demo.sh`
- `scripts/test-ghostty-wrapper.sh`
- `scripts/test-verification-artifacts.sh`
- `scripts/stage-engine-header.sh`
- `scripts/verify-packaging.sh`
- `zig build doctor`
- `zig build ci`

Fast vs slow lanes:

- Fast lane: `.githooks/pre-commit` runs `scripts/verify-commit.sh`, which delegates to the canonical `scripts/verify-fast.sh` gate.
- Slow lane: `scripts/verify-slow.sh` reruns the fast lane, then adds observability, N=50 stress, multiplayer, replay, security, packaging, and release-build checks.
- Soak lane: `scripts/verify-soak.sh` runs a bounded reconnect/session-churn loop and retains per-step logs under `artifacts/verification-lanes/soak/`.
- Demo lane: `scripts/verify-demo.sh` runs the slow lane plus the real DemoApp startup self-test.
- Lane artifacts: `docs/verification-lanes.md` documents retained summaries and per-step logs under `artifacts/verification-lanes/<lane>/<run-id>/`.
- Artifact contract: `scripts/test-verification-artifacts.sh` emits and validates the canonical retained bundle layout used by future room/session/client/compositor/security verification harnesses.
- Failure injection: `scripts/verify-commit-failure.sh host-shell` proves the hook rejects representative lane failures with specific output.
- Ghostty vendor contract: `docs/ghostty-vendor.md` records the pinned snapshot and the wrapper-only boundary.
- Collaborative render profiles: `host/DemoApp/Resources/RenderProfiles.json` pins the PragmataPro geometry contract used by the host.
- Render profile behavior: `docs/render-profiles.md` documents the deterministic sizing rules and failure mode.

Run locally:

- `swift run DemoApp`
