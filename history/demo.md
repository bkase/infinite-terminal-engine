Below is the engineering plan I would hand to a team.

The main recommendation is this: **start with the Zig engine + Metal integration spike first, not the SwiftUI wrapper**. The irreducible technical risk is whether Zig can reliably build a static library that links into a macOS app, drives Metal through a thin ObjC shim, and renders to an offscreen texture with correct ABI layout. The shader itself is native MSL—roughly 20 lines for instanced rectangle fill—so it is not a risk factor. `zig fmt` is the standard formatter; Zig’s build system is explicitly a dependency graph that supports custom steps, generated files, system-installed tools, and concurrent execution. The official site currently lists **0.15.2** as the latest release, and the 0.15.2 release notes still say the build system should be expected to break semver before 1.0, so for this demo I would pin exact tool versions and avoid tracking Zig master. ([Zig Programming Language][1])

For coding standards, make `zig fmt` mandatory and adopt Zig’s published style guide. One useful consequence is naming: Zig’s style guide explicitly discourages vague suffixes like **State**, **Manager**, and **Context**, so I would rename `CanvasState` to `Canvas` or `Scene`, and reserve suffixes only where they carry real meaning. I did not find an official standalone Zig linter in the published Zig tooling/docs, so I would not make a third-party linter a hard gate for this prototype; instead, the mandatory gates should be `zig fmt`, successful compilation, and the unit/integration suites.

## 1. Demo scope and definition of done

This prototype should prove five things, and nothing more:

1. A macOS app on Apple Silicon embeds an `MTKView` in SwiftUI and presents a continuously rendered infinite 2D canvas.
2. All scene logic, camera math, visible-set construction, and render dispatch decisions live in Zig.
3. The GPU renders rectangles via an instanced vertex/fragment pipeline using a native MSL shader, offline-compiled into a `.metallib`. Zig owns the buffer layout, instance data, and draw call parameters.
4. Panning and zooming feel immediate and deterministic.
5. The whole system is testable

Non-goals for this demo:

- no text rendering
- no selection, hit-testing, or editing tools
- no retained scene graph or UI framework in Zig
- no Intel Mac support
- no production asset pipeline

The practical success criterion should be: **large total scene, modest visible set**. I would scope the dataset to something like “thousands of total rectangles, with a typical visible set in the low hundreds.” The instanced vertex/fragment pipeline can handle far more than this on Apple Silicon, but keeping the demo dataset modest avoids incidental complexity in the visible-set builder and upload path.

## 2. Baseline technical decisions

### 2.1 Ownership model

The cleanest version of this prototype is:

- **SwiftUI/AppKit/MetalKit shell** for windowing, input capture, and drawable lifecycle.
- **Zig engine** for all logic and all render decisions.
- **Tiny Objective-C Metal shim** as the default implementation for the final API calls into Metal.

I am deliberately recommending the tiny Objective-C shim as the default, even though the “ultimate hacker” version would push Objective-C runtime calls directly from Zig. The reason is engineering risk management: I verified the Zig build/format/targeting facts from official sources, but I did not find equally clear official current documentation that I would want to bet the whole demo on for direct Zig↔Objective-C interop. So the plan should keep **all logic in Zig**, while treating ObjC as a thin, replaceable FFI membrane around Metal.

That still satisfies the spirit of the brief:

- Swift is just the shell.
- ObjC is just the API membrane.
- Zig owns scene data, camera transforms, visible-set construction, render parameters, and dispatch dimensions. The shader is native MSL—Zig does not author or generate it.

### 2.2 Shader pipeline: native MSL, not Zig→SPIR-V

The shader is written directly in Metal Shading Language. The build pipeline is:

1. Offline-compile `src/shaders/rect_fill.metal` with `xcrun metal -c`.
2. Link with `xcrun metallib`.
3. Stage the resulting `.metallib` into the host app bundle.

**Why not Zig→SPIR-V→SPIRV-Cross→MSL?** That pipeline was the original plan, and it is an impressive engineering flex, but it is entirely self-inflicted risk. Routing a shader through five volatile tool versions (Zig SPIR-V backend, spirv-val, SPIRV-Cross, Metal compiler, metallib linker) just to avoid writing ~20 lines of MSL serves no practical purpose when the target is exclusively Apple Silicon. The goal of this demo is to prove that Zig can drive the **engine and scene logic**—not that Zig can also generate shader source. Keep the 100% Zig engine, but let Metal’s native toolchain own the shader.

The ABI contract between CPU and GPU is still enforced by the packed `extern struct` definitions in `gpu_types.zig` and compile-time layout assertions. The MSL shader simply declares matching struct layouts. If they ever drift, the GPU smoke tests catch it immediately.

Apple’s Metal docs describe offline compilation with `metal -c` and then `metallib`, and Apple also documents optional symbol/source recording flows for debug symbol generation.

### 2.3 Build orchestration

`build.zig` should be the authority for the Zig engine library, generated C header, and shader compilation (via `xcrun metal` / `metallib` custom steps). The host app can still be built in Xcode, but Xcode should consume generated artifacts from `zig-out/` or a staged `HostApp/Generated/` directory. Zig’s build system docs explicitly support custom steps, generated files, and system-installed tools, which is exactly what this pipeline needs. ([Zig Programming Language][2])

### 2.4 Formatting and linting policy

Use this exact policy:

- **Required**: `zig fmt`
- **Required**: compilation and tests
- **Optional**: editor/LSP assistance
- **Not required for this demo**: third-party linter

The reason is simple: `zig fmt` is standardized, while an official standalone linter is not.

## 3. Proposed architecture

## 3.1 Repository layout

```text
/
├── build.zig
├── build.zig.zon
├── include/
│   └── engine.h
├── src/
│   ├── shared/
│   │   ├── gpu_types.zig
│   │   ├── camera_math.zig
│   │   └── color.zig
│   ├── engine/
│   │   ├── api.zig
│   │   ├── canvas.zig
│   │   ├── visible_set.zig
│   │   ├── reference_renderer.zig
│   │   ├── stats.zig
│   │   └── errors.zig
│   ├── shaders/
│   │   └── rect_fill.metal
│   ├── bridge/
│   │   ├── metal_bridge.h
│   │   └── metal_bridge.m
├── host/
│   ├── DemoApp.xcodeproj
│   └── DemoApp/
│       ├── App.swift
│       ├── CanvasView.swift
│       ├── MetalCanvasView.swift
│       ├── RendererCoordinator.swift
│       └── Resources/
├── tests/
│   ├── unit/
│   ├── integration/
│   ├── gpu/
│   └── fixtures/
└── scripts/
    └── doctor.zig
```

## 3.2 Shared types

I would **not** use `[4]f32` for color in the first milestone. For the first milestone, use a packed `u32` RGBA color and explicitly size every GPU-facing struct to a 16-byte multiple. That reduces layout ambiguity and bandwidth at the same time, and the matching MSL struct declarations are trivial to keep in sync.

```zig
/// Canvas-to-screen projection as a column-major 3x2 affine matrix.
/// The shader reconstructs the full 3x3 with an implicit [0, 0, 1] row.
///
/// For the common pan+zoom case the CPU builds:
///   m00 = zoom,  m01 = 0,     tx = -pan_x * zoom
///   m10 = 0,     m11 = zoom,  ty = -pan_y * zoom
///
/// Passing the composed matrix instead of separate pan/zoom scalars means
/// the shader does a single mat-vec multiply, and the CPU side can later
/// add rotation or skew without changing the ABI or the shader.
pub const CameraUniform = extern struct {
    /// Column-major 3x2: [m00, m10, m01, m11, tx, ty]
    transform: [6]f32,
    viewport_width_px: u32,
    viewport_height_px: u32,
};

pub const Rect = extern struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    color_rgba8: u32,
    _pad0: u32 = 0,
    _pad1: u32 = 0,
    _pad2: u32 = 0,
};
```

Why this matters:

- `extern struct` gives you a defined foreign ABI layout on the Zig side.
- `*anyopaque` is the correct Zig type for foreign opaque handles such as Metal objects.
- compile-time offset and size assertions can then lock the contract down.

Required compile-time invariants:

- `@sizeOf(CameraUniform) == 32` (6×f32 = 24 bytes for transform + 2×u32 = 8 bytes for viewport)
- `@sizeOf(Rect) == 32`
- `@offsetOf(Rect, "color_rgba8") == 16`

If you later want float colors, do that in phase 2 after the build pipeline and GPU smoke tests are stable.

## 3.3 Runtime data flow

Each frame should do this:

1. Swift host receives draw callback from `MTKViewDelegate`.
2. Host passes the current drawable texture to Zig.
3. Zig computes current viewport bounds in canvas space.
4. Zig builds the visible rectangle subset from the master scene.
5. Zig updates the camera uniform buffer and visible-rect instance buffer.
6. Zig calls the Metal shim to set up a render pass, bind the pipeline state, bind the camera uniform and instance buffer, issue a single instanced draw call (`drawPrimitives:vertexStart:vertexCount:instanceCount:` with 6 vertices per unit quad and `instanceCount` = visible rect count), end encoding, commit, and present.

### 3.3.1 Why instanced vertex/fragment, not a compute shader

The original plan proposed a "brute-force compute shader" with a per-pixel loop over visible rectangles. That is essentially a software rasterizer running inside a compute kernel—it forces the GPU to execute O(pixels × visible_rects) operations and completely bypasses the hardware rasterizer and the Tile-Based Deferred Rendering (TBDR) architecture that makes Apple Silicon exceptionally efficient.

The instanced vertex/fragment approach is better in every dimension:

- **Less code:** A trivial vertex shader takes a static unit quad (6 vertices, two triangles) and scales/translates each instance using the camera matrix and the instance’s position/size. The fragment shader outputs the instance’s color. The entire MSL file is ~20 lines.
- **Hardware rasterizer does the work:** The GPU’s fixed-function rasterizer fills pixels. No manual bounding-box checks per pixel. No O(pixels × rects) loop.
- **Scales effortlessly:** Instanced drawing on Apple Silicon handles millions of rectangles without breaking a sweat, rendering the "capacity" risk moot.
- **TBDR-friendly:** Apple Silicon’s tile-based architecture is designed for render passes, not compute kernels writing to textures. Using the render pipeline gets you automatic tile memory, early-Z rejection, and efficient blending for free.

The ObjC shim should implement the standard render-pass shape: create render pass descriptor targeting the drawable texture, create render command encoder, set pipeline state, set vertex buffers (camera uniform at index 0, instance buffer at index 1), draw instanced primitives, end encoding, commit.

### 3.4 Coordinate system and projection matrix

Use a **y-down** canvas for the prototype.

That gives you:

- direct mapping from pixel coordinates to canvas coordinates
- fewer sign flips in the shader

Rather than tracking `pan_x`, `pan_y`, and `zoom` as three separate scalars and reconstructing the transform everywhere, maintain a single **3×3 affine transform matrix** on the CPU and upload the 3×2 portion to the GPU as `CameraUniform.transform`. This is mathematically simpler—especially for anchor-point zoom—and it keeps a single source of truth.

The canvas-to-screen transform for the simple pan+zoom case is:

```
          ┌ zoom   0    -pan_x·zoom ┐
    M  =  │  0    zoom  -pan_y·zoom │
          └  0     0         1      ┘
```

The inverse (screen-to-canvas) is:

```
          ┌ 1/zoom   0     pan_x ┐
   M⁻¹ = │  0     1/zoom  pan_y │
          └  0       0       1   ┘
```

For zooming around the cursor, the matrix formulation is clean:

1. Translate so the cursor is at the origin: `T(-cursor)`
2. Scale: `S(new_zoom / old_zoom)`
3. Translate back: `T(+cursor)`
4. Compose: `M' = T(+cursor) · S(ratio) · T(-cursor) · M`

This avoids the error-prone "compute canvas point, update zoom, recompute pan" dance and generalizes trivially if you later want rotation or skew.

Pass the composed 3×2 matrix directly to the GPU uniform (see `CameraUniform.transform`). The shader reconstructs the full 3×3 with an implicit `[0, 0, 1]` bottom row and does a single matrix-vector multiply per pixel. No separate `inv_zoom` or `translate` extraction step is needed.

This is one of the most important unit-test areas: verify that zoom-around-cursor preserves the anchor point, that roundtrip screen↔canvas conversions via the matrix are inverses, and that the uploaded 3×2 matches the full matrix state.

## 3.5 Scene model

Use two arrays:

- `all_rects`: master scene
- `visible_rects`: per-frame filtered upload array

The per-frame visible set is what gets uploaded to the GPU as the instance buffer. The instanced draw call renders exactly `visible_rects.len` instances—the GPU never sees the full scene. CPU-side culling keeps the upload small and the draw call fast.

Painter’s order should be **array order**. That gives you deterministic behavior and straightforward CPU reference rendering.

## 4. Build plan

## 4.1 Required `zig build` steps

I would define these named steps:

- `zig build doctor`
- `zig build fmt`
- `zig build test-unit`
- `zig build shader`
- `zig build test-integration-cpu`
- `zig build test-gpu`
- `zig build host`
- `zig build ci`

`doctor` should fail fast if any required tool is missing:

- pinned Zig version
- `xcrun`
- `metal` (via `xcrun metal`)
- `metallib` (via `xcrun metallib`)

`shader` should expand to this graph:

1. `xcrun metal -c src/shaders/rect_fill.metal -o zig-out/rect_fill.air`
2. `xcrun metallib zig-out/rect_fill.air -o zig-out/rect_fill.metallib`
3. copy/stage `.metallib` into host resources

This is deliberately simple. The shader is ~20 lines of MSL. Drift between CPU struct layout and MSL struct layout is caught by compile-time layout assertions in Zig and by the GPU smoke tests—not by a reflection pipeline.

## 4.2 Build-system policy

Pin these exactly:

- Zig version
- Xcode / Command Line Tools version in CI image

Because the Zig build system is still evolving before 1.0, do not let developer machines float across arbitrary Zig versions. ([Zig Programming Language][1])

## 4.3 Host-app integration policy

Do not make `build.zig` own every aspect of the SwiftUI app. That creates unnecessary complexity. Instead:

- `build.zig` owns engine library, generated C header, and shader artifacts (`.metallib` via `xcrun metal`/`metallib` custom steps)
- Xcode owns the app target
- Xcode consumes staged generated artifacts

That gives you a strong center of gravity without turning the whole stack into one fragile build script.

## 5. Swift host shell

SwiftUI needs AppKit interop here. Apple documents `NSViewRepresentable` as the bridge that lets SwiftUI wrap an AppKit `NSView`. `MTKViewDelegate` provides the draw callback, and `MTKView` exposes `currentDrawable` for the drawable texture. That is exactly the host shell you want. ([Apple Developer][3])

Implementation shape:

- `CanvasRepresentable : NSViewRepresentable`
- `MetalCanvasView : MTKView`
- `Coordinator : NSObject, MTKViewDelegate`

Responsibilities:

- `makeNSView`: create `MTKView`, initialize Metal device, configure pixel format, delegate, `preferredFramesPerSecond = 120` for ProMotion support
- `draw(in:)`: obtain current drawable texture and call `engine_render`
- `drawableSizeWillChange`: call `engine_resize`
- `scrollWheel(with:)`: send pan deltas to Zig
- `magnify(with:)`: send zoom deltas to Zig
- fallback zoom: keyboard shortcut or modifier+scroll

Apple’s trackpad docs explicitly say gestures should supplement, not replace, conventional input, so I would not make pinch-to-zoom the only zoom path. AppKit also exposes `scrollingDeltaX`, `scrollingDeltaY`, and `hasPreciseScrollingDeltas`; that means your input normalization should distinguish precise trackpad deltas from coarser wheel deltas. ([Apple Developer][4])

## 6. Public C ABI

The exported API should be narrow, explicit, and thread-affine.

```zig
pub const EngineStatus = extern enum(c_int) {
    ok = 0,
    invalid_arg = 1,
    not_initialized = 2,
    io_error = 3,
    gpu_error = 4,
    capacity_exceeded = 5,
};

pub const EngineConfig = extern struct {
    max_rects: u32,
    max_visible_rects: u32,
    initial_width_px: u32,
    initial_height_px: u32,
    debug_flags: u32,
};

pub const FrameStats = extern struct {
    total_rects: u32,
    visible_rects: u32,
    width_px: u32,
    height_px: u32,
};

export fn engine_init(
    mtl_device: *anyopaque,
    metallib_path_z: [*:0]const u8,
    cfg: *const EngineConfig,
) EngineStatus;

export fn engine_shutdown() void;

export fn engine_resize(width_px: u32, height_px: u32) void;

export fn engine_pan(delta_x_px: f32, delta_y_px: f32) void;

export fn engine_zoom(delta: f32, anchor_x_px: f32, anchor_y_px: f32) void;

export fn engine_replace_rects(rects: [*]const Rect, len: usize) EngineStatus;

export fn engine_render(drawable_texture: *anyopaque) EngineStatus;

export fn engine_get_stats(out: *FrameStats) void;

export fn engine_last_error_message(buf: [*]u8, len: usize) usize;
```

Notes:

- use `extern struct` for ABI-visible structs
- use `export fn` for the C ABI
- use `*anyopaque` for Metal object handles

### Thread safety

In Apple's ecosystem, the main thread (where AppKit/SwiftUI receives `scrollWheel` and `magnify` events) is fundamentally distinct from the render thread (where `MTKViewDelegate.draw(in:)` is invoked by `MTKView`'s display link). Since this demo targets 120fps on ProMotion displays, the render callback must run on its own thread at the display link's cadence—forcing everything to the main runloop would cap you at the runloop's scheduling granularity and miss frames.

This means `engine_pan` / `engine_zoom` (called from the main thread on input events) and `engine_render` (called from the render thread on `draw(in:)`) will execute concurrently. The engine must handle this.

The solution is **double-buffered camera state** in the Zig engine:

1. Input functions (`engine_pan`, `engine_zoom`, `engine_resize`) write to a **pending** camera state protected by a lightweight lock (a single `std.Thread.Mutex` or an atomic swap).
2. At the top of `engine_render`, the engine atomically snapshots the pending state into the **active** camera state used for that frame's visible-set construction and uniform upload.
3. The visible-set array and instance buffer are rebuilt each frame from the active snapshot—no shared mutable state touches the render path after the snapshot.

This keeps the lock hold time minimal (one atomic swap or a memcpy of the 32-byte `CameraUniform`), avoids any lock contention during the GPU work itself, and satisfies the "no heap allocations in steady state" rule since both camera slots are pre-allocated at init.

The `engine_replace_rects` call is less frequent and can take a slightly broader lock to swap the master scene array. Since rect replacement is a bulk operation (not per-frame), brief contention here is acceptable.

Three important rules:

1. `engine_replace_rects` must **copy** the caller’s memory into engine-owned storage.
2. After `engine_init`, the steady-state render path must perform **no heap allocations**.
3. `engine_init` must allocate all engine-owned memory up front, and `engine_shutdown` must free it completely.

Memory strategy: `engine_init` should create a Zig `FixedBufferAllocator` sized from `EngineConfig.max_rects` and `max_visible_rects` (or a General Purpose Allocator if dynamic sizing is needed later), allocate all buffers — scene storage, visible-set scratch, Metal buffer backing — in one shot, and store the allocator handle in engine-global state. `engine_shutdown` must tear down everything the allocator owns. This makes the lifetime model explicit: the host calls `init`, the engine owns its heap until `shutdown`, and the render loop in between never touches the allocator. The Zig allocator interface makes this easy to enforce — pass a counting wrapper in tests (see U17) that fails on any allocation after init completes.

## 7. Staffing plan

For a prototype with a custom C ABI, a volatile shader pipeline, and tight coupling between all layers, spinning up 5 parallel streams on day one is a recipe for merge conflicts and blocked cycles. **This is a 2-engineer, maybe 3-engineer project for the first two weeks.** Keep the team small until the shader pipeline (S1) and ABI contract (S4) are definitively proven.

### Phase 1: prove the foundation (2 engineers, weeks 1–2)

| Engineer | Primary stream                                                               | Secondary stream                                              |
| -------- | ---------------------------------------------------------------------------- | ------------------------------------------------------------- |
| Eng 1    | S1: Metal integration spike (native MSL shader, ObjC shim, offscreen render) | S4: ABI contract, shared structs, compile-time layout asserts |
| Eng 2    | S2: Core Zig math and scene model                                            | S5: CI/doctor/fmt/test harness scaffolding                    |

S3 (SwiftUI/MTKView shell) can wait. It is blocked by S1 and S4 anyway, and a stub shell takes one engineer a day or two once the ABI is stable.

Eng 1 owns the critical path. The gate to exit Phase 1:

- native MSL shader compiles to `.metallib`
- ObjC shim renders to an offscreen 64×64 texture with deterministic pixels
- Zig engine drives the render through the shim
- ABI structs have compile-time layout tests and a C header
- engine builds as a static library that links from a tiny C harness
- `doctor`, `fmt`, unit-test wiring, and CI shell are operational

### Phase 2: integrate (2–3 engineers, weeks 3–4)

Once the shader pipeline and ABI are proven, expand:

| Work                                                         | Owner       |
| ------------------------------------------------------------ | ----------- |
| Real Metal runtime integration + instanced draw path         | Eng 1       |
| Connect visible-set builder and camera state to engine API   | Eng 2       |
| SwiftUI/MTKView shell against real engine library            | Eng 3 (new) |
| Build-pipeline integration tests, offscreen GPU test harness | Eng 2       |

### Phase 3: polish and validate (full team if needed)

| Work                                              |
| ------------------------------------------------- |
| GPU smoke tests and visual validation             |
| Input normalization, resize, fallback zoom        |
| Performance instrumentation, frame stats          |
| Packaging, resource staging, error-path hardening |
| Demo dataset curation, manual QA, docs            |

The key governance rule remains: **when a stream is on the critical path, one engineer owns it**. The difference from a naive 5-stream plan is that you do not pay the coordination cost of a full team until the foundation is proven and the integration surface is stable.

## 8. Detailed test plan

This is the minimum serious plan.

## 8.1 Unit tests: pure Zig, no Metal, no Swift

These run on every PR.

| ID  | Test                          | What it proves                                                  | Pass criterion                             |
| --- | ----------------------------- | --------------------------------------------------------------- | ------------------------------------------ |
| U01 | `camera_roundtrip`            | `screen_to_canvas` and `canvas_to_screen` are inverses          | roundtrip error under epsilon              |
| U02 | `zoom_anchor_preserved`       | cursor-anchored zoom math is correct                            | anchor canvas point unchanged              |
| U03 | `zoom_clamped`                | zoom never underflows/overflows configured bounds               | exact clamp values                         |
| U04 | `pan_updates_camera`          | panning semantics are correct                                   | expected pan values                        |
| U05 | `rect_contains_edges`         | edge inclusion rules are stable                                 | exact boolean outcomes                     |
| U06 | `visible_set_basic`           | culling works                                                   | expected visible IDs                       |
| U07 | `visible_set_preserves_order` | painter’s order survives culling                                | output order matches input order           |
| U08 | `visible_set_capacity_error`  | overflow is handled explicitly                                  | returns `capacity_exceeded`                |
| U09 | `replace_rects_copies_input`  | caller memory lifetime is decoupled                             | later caller mutation has no effect        |
| U10 | `camera_uniform_layout`       | CPU ABI for uniforms is locked                                  | exact sizes and offsets                    |
| U11 | `rect_layout`                 | GPU upload ABI is locked                                        | exact sizes and offsets                    |
| U12 | `color_pack_unpack_roundtrip` | packed color contract is stable                                 | exact byte equality                        |
| U13 | `cpu_reference_single_rect`   | reference renderer basic correctness                            | expected pixel values at sampled points    |
| U14 | `cpu_reference_overlap`       | painter’s order in reference renderer                           | front rect color wins at overlap center    |
| U15 | `cpu_reference_pan_zoom`      | CPU reference and transform math agree                          | expected pixel values at sampled points    |
| U16 | `engine_state_machine`        | invalid call ordering is rejected                               | correct error codes                        |
| U17 | `steady_state_no_alloc`       | render-prep path is allocation-free after init                  | allocator reports zero allocs              |
| U18 | `camera_snapshot_isolation`   | render sees consistent camera state despite concurrent pan/zoom | snapshot unchanged after concurrent writes |

Note on the CPU reference renderer: its purpose is to validate transform math and painter's-order logic, **not** to be a pixel-perfect oracle for the GPU. Writing a CPU rasterizer that exactly matches Metal's hardware edge-inclusion, floating-point rounding, and half-pixel tie-breaking rules is notoriously difficult and not worth the effort for a prototype. The CPU reference tests (U13–U15) should sample pixels well inside rect interiors—not at edges—and verify expected colors at those points. Edge behavior is validated structurally by the bounding-box and visible-set tests (U05–U07), and visually by the GPU smoke tests.

These unit tests matter because they turn the GPU problem into a much smaller integration problem. If camera math, visible-set construction, ABI layout, and reference rendering are already proven in pure Zig, GPU failures become easy to localize.

## 8.2 Integration tests: build/toolchain/ABI

These are not unit tests. They verify that separately correct pieces actually compose.

| ID  | Test                                  | Layer           | Pass criterion                                   |
| --- | ------------------------------------- | --------------- | ------------------------------------------------ |
| I01 | `metal_compile_smoke`                 | build           | `xcrun metal -c` succeeds on `rect_fill.metal`   |
| I02 | `metallib_build`                      | build           | `xcrun metallib` produces a valid `.metallib`    |
| I03 | `c_header_link_smoke`                 | ABI             | tiny C harness compiles and links against engine |
| I04 | `host_loads_metallib`                 | packaging       | app/test harness can locate staged metallib      |
| I05 | `invalid_metallib_path_fails_cleanly` | init/error path | returns deterministic init error                 |
| I06 | `engine_render_before_init_fails`     | state machine   | returns `not_initialized`                        |

I would run I01–I06 in macOS CI.

## 8.3 GPU integration tests: real Metal, offscreen, deterministic

These are the most important end-to-end tests.

**Important design decision:** these tests do **not** compare GPU output against the CPU reference renderer pixel-for-pixel. Pixel-perfect CPU/GPU equivalence is a trap—Metal's hardware rasterization rules for edge inclusion, floating-point rounding, and half-pixel tie-breaking will not match a naive CPU loop, and debugging those discrepancies will consume more time than building the actual app. Instead, the GPU tests use two strategies:

1. **Structural sampling**: read back specific pixels that are well inside rect interiors (not on edges) and assert expected colors. This catches real bugs (wrong transform, wrong buffer binding, wrong painter's order) without fighting hardware rasterization differences.
2. **Self-consistency**: render the same scene repeatedly and assert identical output, or render with known transforms and assert that sampled interior pixels shift as expected.

Use a headless Metal test harness that:

1. creates `MTLDevice`
2. creates an offscreen texture
3. initializes the engine with the compiled `.metallib`
4. uploads a tiny deterministic scene
5. calls a synchronous test render path
6. reads texture bytes back
7. samples specific interior pixels and asserts expected colors

| ID  | Test                            | Scene                          | Pass criterion                                    |
| --- | ------------------------------- | ------------------------------ | ------------------------------------------------- |
| G01 | `gpu_single_rect_interior`      | one solid rect                 | sampled interior pixel matches rect color         |
| G02 | `gpu_overlap_painter_order`     | overlapping rects              | front rect color at overlap interior              |
| G03 | `gpu_pan_shifts_pixels`         | panned camera                  | sampled pixel shifts by expected pan offset       |
| G04 | `gpu_zoom_scales_rect`          | zoomed camera                  | rect interior covers expected larger pixel region |
| G05 | `gpu_pan_zoom_combo`            | combined transform             | sampled interior pixels at expected positions     |
| G06 | `gpu_empty_scene`               | no rects                       | all sampled pixels are background color           |
| G07 | `gpu_resize_consistency`        | same scene, new dimensions     | interior pixels still correct after resize        |
| G08 | `gpu_visible_set_boundary`      | rects on viewport edges        | partially-visible rect interior pixels correct    |
| G09 | `gpu_max_visible_rects_smoke`   | stress within configured bound | no error, no crash, image non-empty               |
| G10 | `gpu_repeated_render_stability` | same frame many times          | identical output every time                       |

I would keep these image tests small: 32×32, 64×64, maybe 128×128. Small images keep them fast and deterministic. Place sampled pixels at least 2px inside rect boundaries to avoid edge-rule ambiguity.

## 8.4 Host integration tests: Swift/AppKit/MetalKit boundary

These verify the shell specifically.

| ID  | Test                                     | What it proves                | Pass criterion                    |
| --- | ---------------------------------------- | ----------------------------- | --------------------------------- |
| H01 | `mtkview_delegate_calls_engine`          | draw loop is wired            | engine render invoked             |
| H02 | `drawable_size_propagates`               | resize path is wired          | engine sees new size              |
| H03 | `scroll_pan_propagates`                  | scroll event reaches Zig      | camera state changes as expected  |
| H04 | `magnify_zoom_propagates`                | pinch zoom reaches Zig        | camera state changes as expected  |
| H05 | `fallback_zoom_path`                     | non-gesture zoom works        | camera state changes as expected  |
| H06 | `precise_vs_coarse_scroll_normalization` | input normalization is stable | deltas map to expected pan values |

Because AppKit exposes precise-scrolling metadata and because Apple advises gestures should not be the only path for core actions, these tests are not optional. ([Apple Developer][4])

## 8.5 Manual signoff tests

Do not confuse these with automated integration tests. These are demo readiness checks.

- launch from clean checkout on a target Apple Silicon machine
- verify metallib is bundled and loaded
- pan smoothly with trackpad
- pinch to zoom around cursor
- verify wheel or keyboard fallback zoom
- resize window repeatedly
- leave app running and interact for an extended session
- verify no visible flicker, stale frames, or obvious lag
- verify stats overlay reports sane visible-rect counts

## 9. Gates

I would define three gates.

### Commit gate

Runs fast and often.

- `zig fmt`
- unit tests
- C ABI link smoke
- `xcrun metal` / `metallib` shader compilation
- full `metallib` build
- GPU offscreen smoke tests (interior pixel sampling, not pixel-perfect goldens)
- host-shell integration tests

### demo gate

Runs before any demo build is cut.

- release build
- manual signoff matrix
- performance smoke
- packaging verification

## 10. Risk register and mitigations

### Risk 1: Zig↔Metal integration via ObjC shim has unexpected friction

Mitigation: make the Metal integration spike the first critical-path task; keep the ObjC shim as thin as possible; prove offscreen rendering works before building the SwiftUI shell.

### Risk 2: Direct Zig↔Objective-C interop becomes a tarpit

Mitigation: default to a tiny ObjC shim and keep all logic in Zig.

### Risk 3: CPU↔GPU layout drift

Mitigation: use explicit `extern struct`, packed colors, compile-time layout asserts, reflection-generated bindings, and GPU smoke tests that sample interior pixels. Do not rely on pixel-perfect CPU-vs-GPU golden image comparison—Metal's hardware rasterization rules will not match a naive CPU loop at edges, and debugging those discrepancies is not worth the effort for a prototype.

### Risk 4: Main-thread vs render-thread data race

Mitigation: double-buffered camera state in the Zig engine. Input functions write to a pending slot; `engine_render` atomically snapshots the pending state at frame start. Lock hold time is a single memcpy of the 32-byte `CameraUniform`. No shared mutable state during the GPU work itself. This supports 120fps on ProMotion displays without forcing draw calls onto the main runloop.

### Risk 5: Build reproducibility drifts across machines

Mitigation: `doctor` step, pinned tool versions, staged generated artifacts, macOS CI lane.

## 11. What I would do first

I would start with two engineers and this exact order:

1. **Phase 1 (2 engineers, weeks 1–2):**
   - Eng 1 proves the Metal integration end-to-end: native MSL shader → `.metallib`, ObjC shim, Zig engine driving an instanced draw call to an offscreen 64×64 texture. In parallel, Eng 1 defines the ABI contract and compile-time layout tests.
   - Eng 2 builds pure Zig camera math (using the affine matrix model), visible-set construction, and the CPU reference renderer. In parallel, Eng 2 wires up `doctor`, `fmt`, and the unit-test harness.
   - The SwiftUI shell waits. It is blocked by S1 and S4, and takes a day or two once the ABI is stable.

2. **Phase 2 (2–3 engineers, weeks 3–4):** Once the shader pipeline and ABI are proven, add a third engineer for the SwiftUI/MTKView shell. Integrate the real render path. Wire up GPU smoke tests.

3. **Phase 3:** Polish, performance instrumentation, demo dataset, manual QA. Expand team only if needed.

That is the sequence that keeps the critical path narrow, avoids coordination overhead on an unproven foundation, and gives the team objective correctness gates instead of “looks right on my machine.”

If you want, I can turn this directly into an RFC-style engineering spec with sections like “Context,” “Goals,” “Non-goals,” “Design,” “Test Plan,” and “Rollout,” or go one level deeper and write the concrete `build.zig` step graph next.

[1]: https://ziglang.org/?utm_source=chatgpt.com "Home Zig Programming Language"
[2]: https://ziglang.org/learn/build-system/?utm_source=chatgpt.com "Zig Build System"
[3]: https://developer.apple.com/documentation/Metal/using-metal-to-draw-a-view%27s-contents?utm_source=chatgpt.com "Using Metal to draw a view's contents"
[4]: https://developer.apple.com/documentation/appkit/nsevent/hasprecisescrollingdeltas?utm_source=chatgpt.com "hasPreciseScrollingDeltas | Apple Developer Documentation"
