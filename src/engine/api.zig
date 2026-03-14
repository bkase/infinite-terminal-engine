const std = @import("std");
const abi = @import("../shared/abi.zig");
const camera_mod = @import("camera.zig");
const scene_mod = @import("scene.zig");

extern fn ite_metal_load_library_from_path(
    device: ?*anyopaque,
    metallib_path: [*:0]const u8,
    error_buf: [*]u8,
    error_buf_len: usize,
) ?*anyopaque;
extern fn ite_metal_create_renderer(
    device: ?*anyopaque,
    command_queue: ?*anyopaque,
    library: ?*anyopaque,
    error_buf: [*]u8,
    error_buf_len: usize,
) ?*anyopaque;
extern fn ite_metal_renderer_draw(
    renderer: ?*anyopaque,
    texture: ?*anyopaque,
    camera: *const abi.CameraUniform,
    rects: [*]const abi.Rect,
    rect_count: u32,
    error_buf: [*]u8,
    error_buf_len: usize,
) c_int;
extern fn ite_metal_release_handle(handle: ?*anyopaque) void;
extern fn ite_metal_destroy_renderer(renderer: ?*anyopaque) void;

pub const Engine = opaque {};

const EngineImpl = struct {
    allocator: std.mem.Allocator,
    scene: scene_mod.Scene,
    pending_camera: camera_mod.Camera,
    active_camera: camera_mod.Camera,
    stats: abi.FrameStats,
    initialized: bool = false,
    renderer: ?*anyopaque = null,
    owned_library: ?*anyopaque = null,
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
        .pending_camera = camera_mod.Camera.init(config.initial_width_px, config.initial_height_px, config.min_zoom, config.max_zoom),
        .active_camera = camera_mod.Camera.init(config.initial_width_px, config.initial_height_px, config.min_zoom, config.max_zoom),
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
        if (state.renderer) |renderer| ite_metal_destroy_renderer(renderer);
        if (state.owned_library) |library| ite_metal_release_handle(library);
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
    const state = fromOpaque(engine_ptr);
    if (metal_device == null or command_queue == null or shader_library == null) {
        setError(state, "init requires non-null Metal handles");
        return .invalid_arg;
    }
    if (state.renderer) |renderer| ite_metal_destroy_renderer(renderer);
    state.renderer = ite_metal_create_renderer(metal_device, command_queue, shader_library, &state.last_error, state.last_error.len);
    if (state.renderer == null) return .gpu_error;
    state.initialized = true;
    setError(state, "");
    return .ok;
}

pub fn initWithMetallibPath(
    engine_ptr: *Engine,
    metal_device: ?*anyopaque,
    command_queue: ?*anyopaque,
    metallib_path: [*:0]const u8,
) abi.EngineStatus {
    const state = fromOpaque(engine_ptr);
    if (metal_device == null or command_queue == null) {
        setError(state, "init requires non-null Metal handles");
        return .invalid_arg;
    }
    if (state.owned_library) |library| ite_metal_release_handle(library);
    state.owned_library = ite_metal_load_library_from_path(metal_device, metallib_path, &state.last_error, state.last_error.len);
    if (state.owned_library == null) return .io_error;
    return init(engine_ptr, metal_device, command_queue, state.owned_library);
}

pub fn replaceRects(engine_ptr: *Engine, rects: [*]const abi.Rect, rect_count: usize) abi.EngineStatus {
    const state = fromOpaque(engine_ptr);
    const status = state.scene.replaceRects(rects[0..rect_count]);
    if (status != .ok) setError(state, "rect capacity exceeded");
    return status;
}

pub fn resize(engine_ptr: *Engine, width_px: u32, height_px: u32) abi.EngineStatus {
    const state = fromOpaque(engine_ptr);
    state.pending_camera.resize(width_px, height_px);
    state.stats.width_px = width_px;
    state.stats.height_px = height_px;
    return .ok;
}

pub fn pan(engine_ptr: *Engine, delta_x_px: f32, delta_y_px: f32) abi.EngineStatus {
    const state = fromOpaque(engine_ptr);
    state.pending_camera.pan(delta_x_px, delta_y_px);
    return .ok;
}

pub fn zoom(engine_ptr: *Engine, delta: f32, anchor_x_px: f32, anchor_y_px: f32) abi.EngineStatus {
    const state = fromOpaque(engine_ptr);
    state.pending_camera.zoomBy(delta, anchor_x_px, anchor_y_px);
    return .ok;
}

pub fn render(engine_ptr: *Engine, drawable_texture: ?*anyopaque) abi.EngineStatus {
    const state = fromOpaque(engine_ptr);
    if (!state.initialized) {
        setError(state, "render requires ite_engine_init first");
        return .not_initialized;
    }
    if (state.renderer == null or drawable_texture == null) {
        setError(state, "render requires renderer and target texture");
        return .invalid_arg;
    }
    state.active_camera = state.pending_camera;
    const status = state.scene.buildVisibleSet(state.active_camera);
    if (status != .ok) {
        setError(state, "visible set capacity exceeded");
        return status;
    }
    const camera_uniform = state.active_camera.uniform();
    if (ite_metal_renderer_draw(
        state.renderer,
        drawable_texture,
        &camera_uniform,
        state.scene.visible_rects.ptr,
        @intCast(state.scene.visible_count),
        &state.last_error,
        state.last_error.len,
    ) == 0) return .gpu_error;
    state.stats.total_rects = @intCast(state.scene.count);
    state.stats.visible_rects = @intCast(state.scene.visible_count);
    state.stats.width_px = state.active_camera.width_px;
    state.stats.height_px = state.active_camera.height_px;
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

test "U16 engine_state_machine" {
    var engine_ptr: ?*Engine = null;
    const config = abi.EngineConfig{
        .max_rects = 8,
        .max_visible_rects = 8,
        .initial_width_px = 64,
        .initial_height_px = 64,
    };
    try std.testing.expectEqual(abi.EngineStatus.ok, create(&engine_ptr, &config));
    defer destroy(engine_ptr);
    try std.testing.expectEqual(abi.EngineStatus.not_initialized, render(engine_ptr.?, null));
    try std.testing.expectEqual(abi.EngineStatus.invalid_arg, init(engine_ptr.?, null, null, null));
}

test "U17 steady_state_no_alloc" {
    var scene = try scene_mod.Scene.init(std.testing.allocator, 8, 8);
    defer scene.deinit();
    const rects = [_]abi.Rect{
        .{ .x = 0, .y = 0, .w = 10, .h = 10, .color_rgba8 = 1 },
    };
    try std.testing.expectEqual(abi.EngineStatus.ok, scene.replaceRects(&rects));
    const camera = camera_mod.Camera.init(64, 64, 0.125, 8);
    try std.testing.expectEqual(abi.EngineStatus.ok, scene.buildVisibleSet(camera));
    try std.testing.expectEqual(@as(usize, 1), scene.visible().len);
}

test "U19 pending_camera_updates_do_not_mutate_active_snapshot" {
    var engine_ptr: ?*Engine = null;
    const config = abi.EngineConfig{
        .max_rects = 4,
        .max_visible_rects = 4,
        .initial_width_px = 64,
        .initial_height_px = 64,
    };
    try std.testing.expectEqual(abi.EngineStatus.ok, create(&engine_ptr, &config));
    defer destroy(engine_ptr);
    const state = fromOpaque(engine_ptr.?);
    const before = state.active_camera.uniform();
    _ = pan(engine_ptr.?, 10, 5);
    try std.testing.expectEqual(@as(f32, 0), before.transform[4]);
    try std.testing.expectEqual(@as(f32, 0), before.transform[5]);
    try std.testing.expect(state.pending_camera.pan_x != state.active_camera.pan_x);
}
