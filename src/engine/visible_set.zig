const std = @import("std");
const abi = @import("../shared/abi.zig");
const camera_math = @import("../shared/camera_math.zig");

pub const BuildVisibleSetError = error{
    VisibleSetCapacityExceeded,
};

pub fn rectContainsPoint(rect: abi.Rect, point: camera_math.Vec2) bool {
    return point.x >= rect.x and
        point.x <= rect.x + rect.width and
        point.y >= rect.y and
        point.y <= rect.y + rect.height;
}

pub fn rectIntersects(lhs: abi.Rect, rhs: abi.Rect) bool {
    return lhs.x <= rhs.x + rhs.width and
        lhs.x + lhs.width >= rhs.x and
        lhs.y <= rhs.y + rhs.height and
        lhs.y + lhs.height >= rhs.y;
}

pub fn buildVisibleSet(camera: camera_math.Camera, scene_rects: []const abi.Rect, output: []abi.Rect) BuildVisibleSetError![]abi.Rect {
    const viewport = camera.viewportCanvasRect();
    var visible_count: usize = 0;

    for (scene_rects) |rect| {
        if (!rectIntersects(rect, viewport)) continue;
        if (visible_count >= output.len) return error.VisibleSetCapacityExceeded;

        output[visible_count] = rect;
        visible_count += 1;
    }

    return output[0..visible_count];
}

test "U05 rect_contains_edges" {
    const rect = abi.Rect{
        .x = 10.0,
        .y = 20.0,
        .width = 30.0,
        .height = 40.0,
        .color_rgba8 = 0,
    };

    try std.testing.expect(rectContainsPoint(rect, .{ .x = 10.0, .y = 20.0 }));
    try std.testing.expect(rectContainsPoint(rect, .{ .x = 40.0, .y = 60.0 }));
    try std.testing.expect(!rectContainsPoint(rect, .{ .x = 40.1, .y = 60.0 }));
}
