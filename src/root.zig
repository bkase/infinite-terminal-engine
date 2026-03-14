const std = @import("std");

pub const shared = struct {
    pub const abi = @import("shared/abi.zig");
    pub const color = @import("shared/color.zig");
};

pub const engine = struct {
    pub const api = @import("engine/api.zig");
};

pub const CameraUniform = shared.abi.CameraUniform;
pub const Rect = shared.abi.Rect;
pub const EngineStatus = shared.abi.EngineStatus;
pub const EngineConfig = shared.abi.EngineConfig;
pub const EngineStats = shared.abi.EngineStats;
pub const Engine = engine.api.Engine;
pub const ABI_VERSION = shared.abi.ABI_VERSION;

comptime {
    _ = shared.abi;
    _ = shared.color;
    _ = engine.api;
}

test {
    std.testing.refAllDecls(@This());
}

pub export fn ite_engine_header_version() u32 {
    return engine.api.ite_engine_header_version();
}

pub export fn ite_engine_create(out_engine: *?*Engine, config: *const EngineConfig) EngineStatus {
    return engine.api.ite_engine_create(out_engine, config);
}

pub export fn ite_engine_destroy(engine_ptr: ?*Engine) void {
    engine.api.ite_engine_destroy(engine_ptr);
}

pub export fn ite_engine_init(
    engine_ptr: *Engine,
    metal_device: ?*anyopaque,
    command_queue: ?*anyopaque,
    shader_library: ?*anyopaque,
) EngineStatus {
    return engine.api.ite_engine_init(engine_ptr, metal_device, command_queue, shader_library);
}

pub export fn ite_engine_render(
    engine_ptr: *Engine,
    camera: *const CameraUniform,
    rects: [*]const Rect,
    rect_count: u32,
    drawable_texture: ?*anyopaque,
) EngineStatus {
    return engine.api.ite_engine_render(engine_ptr, camera, rects, rect_count, drawable_texture);
}

pub export fn ite_engine_get_stats(engine_ptr: *const Engine, out_stats: *EngineStats) EngineStatus {
    return engine.api.ite_engine_get_stats(engine_ptr, out_stats);
}

pub export fn ite_engine_get_last_error(engine_ptr: *const Engine) [*:0]const u8 {
    return engine.api.ite_engine_get_last_error(engine_ptr);
}
