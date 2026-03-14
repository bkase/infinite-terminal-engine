//! Public root module for the engine library and C ABI exports.

const std = @import("std");

pub const shared = struct {
    pub const abi = @import("shared/abi.zig");
    pub const color = @import("shared/color.zig");
};

pub const engine = struct {
    pub const api = @import("engine/api.zig");
    pub const camera = @import("engine/camera.zig");
    pub const reference_renderer = @import("engine/reference_renderer.zig");
    pub const scene = @import("engine/scene.zig");
};

pub const CameraUniform = shared.abi.CameraUniform;
pub const Rect = shared.abi.Rect;
pub const EngineStatus = shared.abi.EngineStatus;
pub const EngineConfig = shared.abi.EngineConfig;
pub const FrameStats = shared.abi.FrameStats;
pub const Engine = engine.api.Engine;

pub export fn ite_engine_header_version() u32 {
    return engine.api.headerVersion();
}

pub export fn ite_engine_create(out_engine: *?*Engine, config: *const EngineConfig) EngineStatus {
    return engine.api.create(out_engine, config);
}

pub export fn ite_engine_destroy(engine_ptr: ?*Engine) void {
    engine.api.destroy(engine_ptr);
}

pub export fn ite_engine_init(
    engine_ptr: *Engine,
    metal_device: ?*anyopaque,
    command_queue: ?*anyopaque,
    shader_library: ?*anyopaque,
) EngineStatus {
    return engine.api.init(engine_ptr, metal_device, command_queue, shader_library);
}

pub export fn ite_engine_init_with_metallib_path(
    engine_ptr: *Engine,
    metal_device: ?*anyopaque,
    command_queue: ?*anyopaque,
    metallib_path: [*:0]const u8,
) EngineStatus {
    return engine.api.initWithMetallibPath(engine_ptr, metal_device, command_queue, metallib_path);
}

pub export fn ite_engine_replace_rects(
    engine_ptr: *Engine,
    rects: [*]const Rect,
    rect_count: usize,
) EngineStatus {
    return engine.api.replaceRects(engine_ptr, rects, rect_count);
}

pub export fn ite_engine_resize(engine_ptr: *Engine, width_px: u32, height_px: u32) EngineStatus {
    return engine.api.resize(engine_ptr, width_px, height_px);
}

pub export fn ite_engine_pan(engine_ptr: *Engine, delta_x_px: f32, delta_y_px: f32) EngineStatus {
    return engine.api.pan(engine_ptr, delta_x_px, delta_y_px);
}

pub export fn ite_engine_zoom(
    engine_ptr: *Engine,
    delta: f32,
    anchor_x_px: f32,
    anchor_y_px: f32,
) EngineStatus {
    return engine.api.zoom(engine_ptr, delta, anchor_x_px, anchor_y_px);
}

pub export fn ite_engine_render(
    engine_ptr: *Engine,
    drawable_texture: ?*anyopaque,
) EngineStatus {
    return engine.api.render(engine_ptr, drawable_texture);
}

pub export fn ite_engine_render_drawable(
    engine_ptr: *Engine,
    drawable: ?*anyopaque,
) EngineStatus {
    return engine.api.renderDrawable(engine_ptr, drawable);
}

pub export fn ite_engine_get_stats(engine_ptr: *const Engine, out_stats: *FrameStats) EngineStatus {
    return engine.api.getStats(engine_ptr, out_stats);
}

pub export fn ite_engine_get_last_error(engine_ptr: *const Engine) [*:0]const u8 {
    return engine.api.getLastError(engine_ptr);
}

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(shared.abi);
    std.testing.refAllDecls(engine.reference_renderer);
}
