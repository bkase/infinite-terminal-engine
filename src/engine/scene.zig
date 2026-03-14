const std = @import("std");
const abi = @import("../shared/abi.zig");
const camera_math = @import("../shared/camera_math.zig");
const visible_set = @import("visible_set.zig");

pub const SceneStore = struct {
    allocator: std.mem.Allocator,
    scene_rects: []abi.Rect,
    visible_rects: []abi.Rect,
    scene_len: usize = 0,

    pub fn init(allocator: std.mem.Allocator, max_scene_rects: usize, max_visible_rects: usize) !SceneStore {
        return .{
            .allocator = allocator,
            .scene_rects = try allocator.alloc(abi.Rect, max_scene_rects),
            .visible_rects = try allocator.alloc(abi.Rect, max_visible_rects),
        };
    }

    pub fn deinit(self: *SceneStore) void {
        self.allocator.free(self.scene_rects);
        self.allocator.free(self.visible_rects);
    }

    pub fn rects(self: *const SceneStore) []const abi.Rect {
        return self.scene_rects[0..self.scene_len];
    }

    pub fn replaceRects(self: *SceneStore, new_rects: []const abi.Rect) !void {
        if (new_rects.len > self.scene_rects.len) return error.SceneCapacityExceeded;

        @memcpy(self.scene_rects[0..new_rects.len], new_rects);
        self.scene_len = new_rects.len;
    }

    pub fn buildVisibleSet(self: *SceneStore, camera: camera_math.Camera) visible_set.BuildVisibleSetError![]const abi.Rect {
        const visible = try visible_set.buildVisibleSet(camera, self.rects(), self.visible_rects);
        return visible;
    }
};

test "U06 visible_set_basic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var scene = try SceneStore.init(arena.allocator(), 8, 8);
    defer scene.deinit();

    const rects = [_]abi.Rect{
        .{ .x = 0.0, .y = 0.0, .width = 50.0, .height = 50.0, .color_rgba8 = 1 },
        .{ .x = 900.0, .y = 0.0, .width = 50.0, .height = 50.0, .color_rgba8 = 2 },
        .{ .x = 100.0, .y = 100.0, .width = 25.0, .height = 25.0, .color_rgba8 = 3 },
    };
    try scene.replaceRects(&rects);

    const camera = camera_math.Camera.init(640, 480);
    const visible = try scene.buildVisibleSet(camera);

    try std.testing.expectEqual(@as(usize, 2), visible.len);
    try std.testing.expectEqual(@as(u32, 1), visible[0].color_rgba8);
    try std.testing.expectEqual(@as(u32, 3), visible[1].color_rgba8);
}

test "U07 visible_set_preserves_order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var scene = try SceneStore.init(arena.allocator(), 8, 8);
    defer scene.deinit();

    const rects = [_]abi.Rect{
        .{ .x = 200.0, .y = 200.0, .width = 10.0, .height = 10.0, .color_rgba8 = 11 },
        .{ .x = 100.0, .y = 100.0, .width = 10.0, .height = 10.0, .color_rgba8 = 22 },
        .{ .x = 150.0, .y = 150.0, .width = 10.0, .height = 10.0, .color_rgba8 = 33 },
    };
    try scene.replaceRects(&rects);

    const camera = camera_math.Camera.init(640, 480);
    const visible = try scene.buildVisibleSet(camera);

    try std.testing.expectEqual(@as(usize, 3), visible.len);
    try std.testing.expectEqual(@as(u32, 11), visible[0].color_rgba8);
    try std.testing.expectEqual(@as(u32, 22), visible[1].color_rgba8);
    try std.testing.expectEqual(@as(u32, 33), visible[2].color_rgba8);
}

test "U08 visible_set_capacity_error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var scene = try SceneStore.init(arena.allocator(), 8, 1);
    defer scene.deinit();

    const rects = [_]abi.Rect{
        .{ .x = 0.0, .y = 0.0, .width = 50.0, .height = 50.0, .color_rgba8 = 1 },
        .{ .x = 10.0, .y = 10.0, .width = 50.0, .height = 50.0, .color_rgba8 = 2 },
    };
    try scene.replaceRects(&rects);

    const camera = camera_math.Camera.init(640, 480);
    try std.testing.expectError(error.VisibleSetCapacityExceeded, scene.buildVisibleSet(camera));
}

test "U09 replace_rects_copies_input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var scene = try SceneStore.init(arena.allocator(), 8, 8);
    defer scene.deinit();

    var rects = [_]abi.Rect{
        .{ .x = 0.0, .y = 0.0, .width = 20.0, .height = 20.0, .color_rgba8 = 77 },
    };
    try scene.replaceRects(&rects);
    rects[0].x = 999.0;
    rects[0].color_rgba8 = 12;

    const stored = scene.rects();
    try std.testing.expectEqual(@as(f32, 0.0), stored[0].x);
    try std.testing.expectEqual(@as(u32, 77), stored[0].color_rgba8);
}
