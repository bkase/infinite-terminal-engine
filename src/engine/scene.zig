//! Scene storage and visible-set construction for rectangle batches.

const std = @import("std");
const Allocator = std.mem.Allocator;
const abi = @import("../shared/abi.zig");
const camera_mod = @import("camera.zig");

/// Stores the full rect list plus the visible subset for the active frame.
pub const Scene = struct {
    allocator: Allocator,
    all_rects: []abi.Rect,
    visible_rects: []abi.Rect,
    count: usize = 0,
    visible_count: usize = 0,

    pub fn init(allocator: Allocator, max_rects: usize, max_visible_rects: usize) !Scene {
        return .{
            .allocator = allocator,
            .all_rects = try allocator.alloc(abi.Rect, max_rects),
            .visible_rects = try allocator.alloc(abi.Rect, max_visible_rects),
        };
    }

    pub fn deinit(self: *Scene) void {
        self.allocator.free(self.visible_rects);
        self.allocator.free(self.all_rects);
    }

    pub fn replaceRects(self: *Scene, rects: []const abi.Rect) abi.EngineStatus {
        if (rects.len > self.all_rects.len) return .capacity_exceeded;
        @memcpy(self.all_rects[0..rects.len], rects);
        self.count = rects.len;
        self.visible_count = 0;
        return .ok;
    }

    pub fn buildVisibleSet(self: *Scene, camera: camera_mod.Camera) abi.EngineStatus {
        const bounds = camera.viewBounds();
        var visible_len: usize = 0;
        for (self.all_rects[0..self.count]) |rect| {
            if (!rectIntersectsBounds(rect, bounds)) continue;
            if (visible_len >= self.visible_rects.len) return .capacity_exceeded;
            self.visible_rects[visible_len] = rect;
            visible_len += 1;
        }
        self.visible_count = visible_len;
        return .ok;
    }

    pub fn visible(self: *const Scene) []const abi.Rect {
        return self.visible_rects[0..self.visible_count];
    }
};

pub fn rectContainsPoint(rect: abi.Rect, x: f32, y: f32) bool {
    return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h;
}

pub fn rectIntersectsBounds(rect: abi.Rect, bounds: camera_mod.ViewBounds) bool {
    const rect_max_x = rect.x + rect.w;
    const rect_max_y = rect.y + rect.h;
    return rect.x <= bounds.max_x and rect_max_x >= bounds.min_x and rect.y <= bounds.max_y and rect_max_y >= bounds.min_y;
}

test "U05 rect_contains_edges" {
    const rect = abi.Rect{ .x = 10, .y = 20, .w = 30, .h = 40, .color_rgba8 = 0 };
    try std.testing.expect(rectContainsPoint(rect, 10, 20));
    try std.testing.expect(rectContainsPoint(rect, 40, 60));
    try std.testing.expect(!rectContainsPoint(rect, 41, 60));
}

test "U06 visible_set_basic" {
    var scene = try Scene.init(std.testing.allocator, 4, 4);
    defer scene.deinit();
    const rects = [_]abi.Rect{
        .{ .x = 0, .y = 0, .w = 40, .h = 40, .color_rgba8 = 1 },
        .{ .x = 200, .y = 200, .w = 10, .h = 10, .color_rgba8 = 2 },
    };
    try std.testing.expectEqual(abi.EngineStatus.ok, scene.replaceRects(&rects));
    const camera = camera_mod.Camera.init(100, 100, 0.125, 8);
    try std.testing.expectEqual(abi.EngineStatus.ok, scene.buildVisibleSet(camera));
    try std.testing.expectEqual(@as(usize, 1), scene.visible().len);
    try std.testing.expectEqual(@as(u32, 1), scene.visible()[0].color_rgba8);
}

test "U07 visible_set_preserves_order" {
    var scene = try Scene.init(std.testing.allocator, 4, 4);
    defer scene.deinit();
    const rects = [_]abi.Rect{
        .{ .x = 0, .y = 0, .w = 10, .h = 10, .color_rgba8 = 1 },
        .{ .x = 5, .y = 5, .w = 10, .h = 10, .color_rgba8 = 2 },
    };
    try std.testing.expectEqual(abi.EngineStatus.ok, scene.replaceRects(&rects));
    const camera = camera_mod.Camera.init(100, 100, 0.125, 8);
    try std.testing.expectEqual(abi.EngineStatus.ok, scene.buildVisibleSet(camera));
    try std.testing.expectEqual(@as(u32, 1), scene.visible()[0].color_rgba8);
    try std.testing.expectEqual(@as(u32, 2), scene.visible()[1].color_rgba8);
}

test "U08 visible_set_capacity_error" {
    var scene = try Scene.init(std.testing.allocator, 4, 1);
    defer scene.deinit();
    const rects = [_]abi.Rect{
        .{ .x = 0, .y = 0, .w = 10, .h = 10, .color_rgba8 = 1 },
        .{ .x = 5, .y = 5, .w = 10, .h = 10, .color_rgba8 = 2 },
    };
    try std.testing.expectEqual(abi.EngineStatus.ok, scene.replaceRects(&rects));
    const camera = camera_mod.Camera.init(100, 100, 0.125, 8);
    try std.testing.expectEqual(abi.EngineStatus.capacity_exceeded, scene.buildVisibleSet(camera));
}

test "U09 replace_rects_copies_input" {
    var scene = try Scene.init(std.testing.allocator, 4, 4);
    defer scene.deinit();
    var rects = [_]abi.Rect{
        .{ .x = 0, .y = 0, .w = 10, .h = 10, .color_rgba8 = 1 },
    };
    try std.testing.expectEqual(abi.EngineStatus.ok, scene.replaceRects(&rects));
    rects[0].color_rgba8 = 9;
    try std.testing.expectEqual(@as(u32, 1), scene.all_rects[0].color_rgba8);
}
