const std = @import("std");
const root = @import("root.zig");
const c = @cImport({
    @cInclude("metal_bridge.h");
});

const staged_metallib_path = "host/DemoApp/Resources/rect_fill.metallib";

fn colorAt(pixels: []const u8, width: usize, x: usize, y: usize) u32 {
    const offset = (y * width + x) * 4;
    return (@as(u32, pixels[offset]) << 24) |
        (@as(u32, pixels[offset + 1]) << 16) |
        (@as(u32, pixels[offset + 2]) << 8) |
        @as(u32, pixels[offset + 3]);
}

fn createEngine(width: u32, height: u32) !*root.Engine {
    var engine: ?*root.Engine = null;
    const config = root.EngineConfig{
        .max_rects = 64,
        .max_visible_rects = 64,
        .initial_width_px = width,
        .initial_height_px = height,
    };
    try std.testing.expectEqual(root.EngineStatus.ok, root.ite_engine_create(&engine, &config));
    return engine.?;
}

fn createGpuContext(width: u32, height: u32) !struct {
    device: *anyopaque,
    queue: *anyopaque,
    texture: *anyopaque,
} {
    var error_buf = [_]u8{0} ** 256;
    const device = c.ite_metal_create_system_device() orelse return error.UnexpectedNull;
    errdefer c.ite_metal_release_handle(device);
    const queue = c.ite_metal_create_command_queue(device) orelse return error.UnexpectedNull;
    errdefer c.ite_metal_release_handle(queue);
    const texture = c.ite_metal_create_offscreen_texture(device, width, height, &error_buf, error_buf.len) orelse {
        std.debug.print("texture error: {s}\n", .{std.mem.sliceTo(&error_buf, 0)});
        return error.UnexpectedNull;
    };
    return .{
        .device = @ptrCast(device),
        .queue = @ptrCast(queue),
        .texture = @ptrCast(texture),
    };
}

fn destroyGpuContext(ctx: anytype) void {
    c.ite_metal_release_handle(ctx.texture);
    c.ite_metal_release_handle(ctx.queue);
    c.ite_metal_release_handle(ctx.device);
}

fn readPixels(texture: *anyopaque, allocator: std.mem.Allocator, width: usize, height: usize) ![]u8 {
    var error_buf = [_]u8{0} ** 256;
    const pixels = try allocator.alloc(u8, width * height * 4);
    errdefer allocator.free(pixels);
    if (c.ite_metal_texture_read_rgba8(texture, pixels.ptr, pixels.len, &error_buf, error_buf.len) == 0) {
        std.debug.print("readback error: {s}\n", .{std.mem.sliceTo(&error_buf, 0)});
        return error.ReadbackFailed;
    }
    return pixels;
}

fn initEngineWithPath(engine: *root.Engine, device: *anyopaque, queue: *anyopaque) !void {
    try std.testing.expectEqual(
        root.EngineStatus.ok,
        root.ite_engine_init_with_metallib_path(engine, device, queue, staged_metallib_path),
    );
}

test "I05 invalid_metallib_path_fails_cleanly" {
    const engine = try createEngine(32, 32);
    defer root.ite_engine_destroy(engine);
    const ctx = try createGpuContext(32, 32);
    defer destroyGpuContext(ctx);

    try std.testing.expectEqual(
        root.EngineStatus.io_error,
        root.ite_engine_init_with_metallib_path(engine, ctx.device, ctx.queue, "/definitely/missing.metallib"),
    );
}

test "G01 gpu_single_rect_interior" {
    const engine = try createEngine(64, 64);
    defer root.ite_engine_destroy(engine);
    const ctx = try createGpuContext(64, 64);
    defer destroyGpuContext(ctx);
    try initEngineWithPath(engine, ctx.device, ctx.queue);

    const rects = [_]root.Rect{
        .{ .x = 8, .y = 8, .w = 20, .h = 20, .color_rgba8 = 0xff0000ff },
    };
    try std.testing.expectEqual(root.EngineStatus.ok, root.ite_engine_replace_rects(engine, &rects, rects.len));
    try std.testing.expectEqual(root.EngineStatus.ok, root.ite_engine_render(engine, ctx.texture));

    const pixels = try readPixels(ctx.texture, std.testing.allocator, 64, 64);
    defer std.testing.allocator.free(pixels);
    try std.testing.expectEqual(@as(u32, 0xff0000ff), colorAt(pixels, 64, 16, 16));
}

test "G02 gpu_overlap_painter_order" {
    const engine = try createEngine(64, 64);
    defer root.ite_engine_destroy(engine);
    const ctx = try createGpuContext(64, 64);
    defer destroyGpuContext(ctx);
    try initEngineWithPath(engine, ctx.device, ctx.queue);

    const rects = [_]root.Rect{
        .{ .x = 4, .y = 4, .w = 40, .h = 40, .color_rgba8 = 0x00ff00ff },
        .{ .x = 16, .y = 16, .w = 24, .h = 24, .color_rgba8 = 0x0000ffff },
    };
    try std.testing.expectEqual(root.EngineStatus.ok, root.ite_engine_replace_rects(engine, &rects, rects.len));
    try std.testing.expectEqual(root.EngineStatus.ok, root.ite_engine_render(engine, ctx.texture));

    const pixels = try readPixels(ctx.texture, std.testing.allocator, 64, 64);
    defer std.testing.allocator.free(pixels);
    try std.testing.expectEqual(@as(u32, 0x0000ffff), colorAt(pixels, 64, 24, 24));
}

test "G06 gpu_empty_scene" {
    const engine = try createEngine(32, 32);
    defer root.ite_engine_destroy(engine);
    const ctx = try createGpuContext(32, 32);
    defer destroyGpuContext(ctx);
    try initEngineWithPath(engine, ctx.device, ctx.queue);

    const rects = [_]root.Rect{};
    try std.testing.expectEqual(root.EngineStatus.ok, root.ite_engine_replace_rects(engine, &rects, rects.len));
    try std.testing.expectEqual(root.EngineStatus.ok, root.ite_engine_render(engine, ctx.texture));

    const pixels = try readPixels(ctx.texture, std.testing.allocator, 32, 32);
    defer std.testing.allocator.free(pixels);
    try std.testing.expectEqual(@as(u32, 0x000000ff), colorAt(pixels, 32, 4, 4));
}

test "G10 gpu_repeated_render_stability" {
    const engine = try createEngine(32, 32);
    defer root.ite_engine_destroy(engine);
    const ctx = try createGpuContext(32, 32);
    defer destroyGpuContext(ctx);
    try initEngineWithPath(engine, ctx.device, ctx.queue);

    const rects = [_]root.Rect{
        .{ .x = 4, .y = 4, .w = 12, .h = 12, .color_rgba8 = 0xffffffff },
    };
    try std.testing.expectEqual(root.EngineStatus.ok, root.ite_engine_replace_rects(engine, &rects, rects.len));

    try std.testing.expectEqual(root.EngineStatus.ok, root.ite_engine_render(engine, ctx.texture));
    const first = try readPixels(ctx.texture, std.testing.allocator, 32, 32);
    defer std.testing.allocator.free(first);

    try std.testing.expectEqual(root.EngineStatus.ok, root.ite_engine_render(engine, ctx.texture));
    const second = try readPixels(ctx.texture, std.testing.allocator, 32, 32);
    defer std.testing.allocator.free(second);

    try std.testing.expectEqualSlices(u8, first, second);
}

test "I08 render_updates_stats_from_active_snapshot" {
    const engine = try createEngine(64, 64);
    defer root.ite_engine_destroy(engine);
    const ctx = try createGpuContext(64, 64);
    defer destroyGpuContext(ctx);
    try initEngineWithPath(engine, ctx.device, ctx.queue);

    const rects = [_]root.Rect{
        .{ .x = 8, .y = 8, .w = 12, .h = 12, .color_rgba8 = 0xffffffff },
        .{ .x = 200, .y = 200, .w = 12, .h = 12, .color_rgba8 = 0x00ffffff },
    };
    try std.testing.expectEqual(root.EngineStatus.ok, root.ite_engine_replace_rects(engine, &rects, rects.len));
    try std.testing.expectEqual(root.EngineStatus.ok, root.ite_engine_pan(engine, 8, 0));

    var stats_before: root.FrameStats = .{};
    try std.testing.expectEqual(root.EngineStatus.ok, root.ite_engine_get_stats(engine, &stats_before));
    try std.testing.expectEqual(@as(u32, 0), stats_before.total_rects);

    try std.testing.expectEqual(root.EngineStatus.ok, root.ite_engine_render(engine, ctx.texture));

    var stats_after: root.FrameStats = .{};
    try std.testing.expectEqual(root.EngineStatus.ok, root.ite_engine_get_stats(engine, &stats_after));
    try std.testing.expectEqual(@as(u32, 2), stats_after.total_rects);
    try std.testing.expectEqual(@as(u32, 1), stats_after.visible_rects);
    try std.testing.expectEqual(@as(u32, 64), stats_after.width_px);
    try std.testing.expectEqual(@as(u32, 64), stats_after.height_px);
}
