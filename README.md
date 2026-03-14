# Infinite Terminal Engine

Prototype for an Apple Silicon macOS infinite 2D canvas with:

- Zig engine and exported C ABI
- Native MSL shader pipeline
- Thin Objective-C Metal bridge
- SwiftUI/MetalKit host shell

Verification entrypoints:

- `scripts/install-hooks.sh`
- `zig build doctor`
- `zig build shader-air`
- `zig build shader-metallib`
- `zig build shader`
- `zig build ci`
- `scripts/verify-demo.sh`

Shader artifact contract:

- `zig build shader-air` installs `zig-out/shaders/rect_fill.air`
- `zig build shader-metallib` installs `zig-out/shaders/rect_fill.metallib`
- `zig build shader` stages `host/DemoApp/Resources/rect_fill.metallib` for the Swift host and metallib load tests
