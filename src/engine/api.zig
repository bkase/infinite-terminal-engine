const std = @import("std");
const abi = @import("../shared/abi.zig");
const camera_mod = @import("camera.zig");
const scene_mod = @import("scene.zig");

pub const Engine = opaque {};

const EngineImpl = struct {
    allocator: std.mem.Allocator,
    scene: scene_mod.Scene,
    camera: camera_mod.Camera,
    stats: abi.FrameStats,
    initialized: bool = false,
    last_error: [256:0]u8 = [_:0]u8{0} ** 256,
};

fn fromOpaque(engine_ptr: *Engine) *EngineImpl {
    return @ptrCast(@alignCast(engine_ptr));
}

fn fromOpaqueConst(engine_ptr: *const Engine) *const EngineImpl {
    return @ptrCast(@alignCast(engine_ptr));
}

fn setError(engine: *EngineImpl, message: []const u8) void {
    @memset(engine.last_error[0..], 0);
    const len = @min(message.len, engine.last_error.len - 1);
    @memcpy(engine.last_error[0..len], message[0..len]);
}

pub fn headerVersion() u32 {
    return abi.ABI_VERSION;
}

pub fn create(out_engine: *?*Engine, config: *const abi.EngineConfig) abi.EngineStatus {
    if (config.abi_version != abi.ABI_VERSION) {
        out_engine.* = null;
        return .invalid_arg;
    }

    const allocator = std.heap.c_allocator;
    const scene = scene_mod.Scene.init(allocator, config.max_rects, config.max_visible_rects) catch {
        out_engine.* = null;
        return .capacity_exceeded;
    };
    const state = allocator.create(EngineImpl) catch {
        var temp_scene = scene;
        temp_scene.deinit();
        out_engine.* = null;
        return .capacity_exceeded;
    };
    state.* = .{
        .allocator = allocator,
        .scene = scene,
        .camera = camera_mod.Camera.init(config.initial_width_px, config.initial_height_px, config.min_zoom, config.max_zoom),
        .stats = .{
            .width_px = config.initial_width_px,
            .height_px = config.initial_height_px,
        },
    };
    out_engine.* = @ptrCast(state);
    return .ok;
}

pub fn destroy(engine_ptr: ?*Engine) void {
    if (engine_ptr) |engine| {
        const state = fromOpaque(engine);
        state.scene.deinit();
        state.allocator.destroy(state);
    }
}

pub fn init(
    engine_ptr: *Engine,
    metal_device: ?*anyopaque,
    command_queue: ?*anyopaque,
    shader_library: ?*anyopaque,
) abi.EngineStatus {
    _ = metal_device;
    _ = command_queue;
    _ = shader_library;
    const state = fromOpaque(engine_ptr);
    state.initialized = true;
    setError(state, "");
    return .ok;
}

pub fn replaceRects(engine_ptr: *Engine, rects: [*]const abi.Rect, rect_count: usize) abi.EngineStatus {
    const state = fromOpaque(engine_ptr);
    const status = state.scene.replaceRects(rects[0..rect_count]);
    if (status != .ok) setError(state, "rect capacity exceeded");
    return status;
}

pub fn resize(engine_ptr: *Engine, width_px: u32, height_px: u32) abi.EngineStatus {
    const state = fromOpaque(engine_ptr);
    state.camera.resize(width_px, height_px);
    state.stats.width_px = width_px;
    state.stats.height_px = height_px;
    return .ok;
}

pub fn pan(engine_ptr: *Engine, delta_x_px: f32, delta_y_px: f32) abi.EngineStatus {
    const state = fromOpaque(engine_ptr);
    state.camera.pan(delta_x_px, delta_y_px);
    return .ok;
}

pub fn zoom(engine_ptr: *Engine, delta: f32, anchor_x_px: f32, anchor_y_px: f32) abi.EngineStatus {
    const state = fromOpaque(engine_ptr);
    state.camera.zoomBy(delta, anchor_x_px, anchor_y_px);
    return .ok;
}

pub fn render(engine_ptr: *Engine, drawable_texture: ?*anyopaque) abi.EngineStatus {
    _ = drawable_texture;
    const state = fromOpaque(engine_ptr);
    if (!state.initialized) {
        setError(state, "render requires ite_engine_init first");
        return .not_initialized;
    }
    const status = state.scene.buildVisibleSet(state.camera);
    if (status != .ok) {
        setError(state, "visible set capacity exceeded");
        return status;
    }
    state.stats.total_rects = @intCast(state.scene.count);
    state.stats.visible_rects = @intCast(state.scene.visible_count);
    setError(state, "");
    return .ok;
}

pub fn getStats(engine_ptr: *const Engine, out_stats: *abi.FrameStats) abi.EngineStatus {
    out_stats.* = fromOpaqueConst(engine_ptr).stats;
    return .ok;
}

pub fn getLastError(engine_ptr: *const Engine) [*:0]const u8 {
    return @ptrCast(&fromOpaqueConst(engine_ptr).last_error);
}
