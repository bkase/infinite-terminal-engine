# Infinite Terminal Engine

Prototype for an Apple Silicon macOS infinite 2D canvas with:

- Zig engine and exported C ABI
- Native MSL shader pipeline
- Thin Objective-C Metal bridge
- SwiftUI/MetalKit host shell

Verification entrypoints:

- `scripts/install-hooks.sh`
- `scripts/stage-engine-header.sh`
- `scripts/verify-packaging.sh`
- `zig build doctor`
- `zig build ci`
- `scripts/verify-demo.sh`

Run locally:

- `swift run DemoApp`
