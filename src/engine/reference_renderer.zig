const std = @import("std");
const abi = @import("../shared/abi.zig");
const color = @import("../shared/color.zig");
const camera_mod = @import("camera.zig");

pub const ReferenceRenderer = struct {
    allocator: std.mem.Allocator,
    pixels: []u32,
    width: usize,
    height: usize,
    background_rgba8: u32 = 0x000000ff,

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !ReferenceRenderer {
        const pixels = try allocator.alloc(u32, width * height);
        return .{
            .allocator = allocator,
            .pixels = pixels,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: *ReferenceRenderer) void {
        self.allocator.free(self.pixels);
    }

    pub fn render(self: *ReferenceRenderer, camera: camera_mod.Camera, rects: []const abi.Rect) void {
        @memset(self.pixels, self.background_rgba8);
        for (rects) |rect| self.fillRect(camera, rect);
    }

    pub fn pixel(self: *const ReferenceRenderer, x: usize, y: usize) u32 {
        return self.pixels[y * self.width + x];
    }

    fn fillRect(self: *ReferenceRenderer, camera: camera_mod.Camera, rect: abi.Rect) void {
        const top_left = camera.canvasToScreen(rect.x, rect.y);
        const bottom_right = camera.canvasToScreen(rect.x + rect.w, rect.y + rect.h);
        const min_x: i32 = @intFromFloat(@floor(@min(top_left.x, bottom_right.x)));
        const max_x: i32 = @intFromFloat(@ceil(@max(top_left.x, bottom_right.x)));
        const min_y: i32 = @intFromFloat(@floor(@min(top_left.y, bottom_right.y)));
        const max_y: i32 = @intFromFloat(@ceil(@max(top_left.y, bottom_right.y)));

        var y = min_y;
        while (y < max_y) : (y += 1) {
            if (y < 0 or y >= self.height) continue;
            var x = min_x;
            while (x < max_x) : (x += 1) {
                if (x < 0 or x >= self.width) continue;
                const sample = camera.screenToCanvas(@as(f32, @floatFromInt(x)) + 0.5, @as(f32, @floatFromInt(y)) + 0.5);
                if (sample.x >= rect.x and sample.x < rect.x + rect.w and sample.y >= rect.y and sample.y < rect.y + rect.h) {
                    self.pixels[@as(usize, @intCast(y)) * self.width + @as(usize, @intCast(x))] = rect.color_rgba8;
                }
            }
        }
    }
};

test "U13 cpu_reference_single_rect" {
    var renderer = try ReferenceRenderer.init(std.testing.allocator, 32, 32);
    defer renderer.deinit();
    const camera = camera_mod.Camera.init(32, 32, 0.125, 8);
    const rects = [_]abi.Rect{
        .{ .x = 4, .y = 5, .w = 10, .h = 8, .color_rgba8 = color.packRgba8(0xff, 0, 0, 0xff) },
    };
    renderer.render(camera, &rects);
    try std.testing.expectEqual(rects[0].color_rgba8, renderer.pixel(8, 8));
}

test "U14 cpu_reference_overlap" {
    var renderer = try ReferenceRenderer.init(std.testing.allocator, 32, 32);
    defer renderer.deinit();
    const camera = camera_mod.Camera.init(32, 32, 0.125, 8);
    const rects = [_]abi.Rect{
        .{ .x = 4, .y = 4, .w = 16, .h = 16, .color_rgba8 = color.packRgba8(0, 0xff, 0, 0xff) },
        .{ .x = 8, .y = 8, .w = 12, .h = 12, .color_rgba8 = color.packRgba8(0, 0, 0xff, 0xff) },
    };
    renderer.render(camera, &rects);
    try std.testing.expectEqual(rects[1].color_rgba8, renderer.pixel(12, 12));
}

test "U15 cpu_reference_pan_zoom" {
    var renderer = try ReferenceRenderer.init(std.testing.allocator, 64, 64);
    defer renderer.deinit();
    var camera = camera_mod.Camera.init(64, 64, 0.125, 8);
    camera.pan(10, 10);
    camera.zoomBy(2, 20, 20);
    const rects = [_]abi.Rect{
        .{ .x = 15, .y = 15, .w = 8, .h = 8, .color_rgba8 = color.packRgba8(0xff, 0xff, 0, 0xff) },
    };
    renderer.render(camera, &rects);
    try std.testing.expectEqual(rects[0].color_rgba8, renderer.pixel(32, 32));
}
