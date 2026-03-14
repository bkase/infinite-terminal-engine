const std = @import("std");
const abi = @import("../shared/abi.zig");

pub const Engine = opaque {};

const EngineImpl = struct {
    allocator: std.mem.Allocator,
    config: abi.EngineConfig,
    stats: abi.EngineStats,
    initialized: bool = false,
    last_error: [255:0]u8 = [_:0]u8{0} ** 255,
};

fn fromOpaque(engine: *Engine) *EngineImpl {
    return @ptrCast(@alignCast(engine));
}

fn statusFromError(err: anyerror) abi.EngineStatus {
    return switch (err) {
        error.OutOfMemory => .out_of_memory,
        else => .invalid_argument,
    };
}

fn setError(engine: ?*EngineImpl, comptime fmt: []const u8, args: anytype) void {
    if (engine) |state| {
        _ = std.fmt.bufPrintZ(&state.last_error, fmt, args) catch {
            state.last_error[0] = 0;
        };
    }
}

fn updateStatus(engine: ?*EngineImpl, status: abi.EngineStatus, comptime fmt: []const u8, args: anytype) abi.EngineStatus {
    if (engine) |state| {
        state.stats.last_status = status;
        setError(state, fmt, args);
    }
    return status;
}

fn createEngine(config: abi.EngineConfig) !*EngineImpl {
    const allocator = std.heap.c_allocator;
    const state = try allocator.create(EngineImpl);
    state.* = .{
        .allocator = allocator,
        .config = config,
        .stats = .{
            .last_status = .ok,
        },
    };
    return state;
}

fn destroyEngine(state: *EngineImpl) void {
    state.allocator.destroy(state);
}

/// Call all API functions from the same thread that owns the engine.
/// Foreign Metal handles remain owned by the caller; the engine only borrows them.
pub fn ite_engine_header_version() u32 {
    return abi.ABI_VERSION;
}

pub fn ite_engine_create(out_engine: *?*Engine, config: *const abi.EngineConfig) abi.EngineStatus {
    if (config.abi_version != abi.ABI_VERSION) {
        out_engine.* = null;
        return .invalid_argument;
    }

    const state = createEngine(config.*) catch |err| {
        out_engine.* = null;
        return statusFromError(err);
    };

    state.last_error[0] = 0;
    out_engine.* = @ptrCast(state);
    return .ok;
}

pub fn ite_engine_destroy(engine: ?*Engine) void {
    if (engine) |opaque_engine| {
        destroyEngine(fromOpaque(opaque_engine));
    }
}

pub fn ite_engine_init(
    engine: *Engine,
    metal_device: ?*anyopaque,
    command_queue: ?*anyopaque,
    shader_library: ?*anyopaque,
) abi.EngineStatus {
    const state = fromOpaque(engine);
    if (metal_device == null or command_queue == null or shader_library == null) {
        return updateStatus(state, .invalid_argument, "init requires non-null Metal handles", .{});
    }

    state.initialized = true;
    state.last_error[0] = 0;
    state.stats.last_status = .ok;
    return .ok;
}

pub fn ite_engine_render(
    engine: *Engine,
    camera: *const abi.CameraUniform,
    rects: [*]const abi.Rect,
    rect_count: u32,
    drawable_texture: ?*anyopaque,
) abi.EngineStatus {
    const state = fromOpaque(engine);
    _ = camera;
    _ = rects;
    _ = drawable_texture;

    if (!state.initialized) {
        return updateStatus(state, .failed_precondition, "render requires ite_engine_init first", .{});
    }

    state.stats.visible_rect_count = rect_count;
    state.stats.draw_rect_count = rect_count;
    state.last_error[0] = 0;
    state.stats.last_status = .ok;
    return .ok;
}

pub fn ite_engine_get_stats(engine: *const Engine, out_stats: *abi.EngineStats) abi.EngineStatus {
    const state: *const EngineImpl = @ptrCast(@alignCast(engine));
    out_stats.* = state.stats;
    return .ok;
}

pub fn ite_engine_get_last_error(engine: *const Engine) [*:0]const u8 {
    const state: *const EngineImpl = @ptrCast(@alignCast(engine));
    return @ptrCast(&state.last_error);
}
