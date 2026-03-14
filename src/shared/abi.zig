const std = @import("std");

pub const ABI_VERSION: u32 = 1;

pub const CameraUniform = extern struct {
    transform: [6]f32,
    viewport_width_px: u32,
    viewport_height_px: u32,
};

pub const Rect = extern struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    color_rgba8: u32,
    _pad0: u32 = 0,
    _pad1: u32 = 0,
    _pad2: u32 = 0,
};

pub const EngineStatus = enum(c_int) {
    ok = 0,
    invalid_argument = 1,
    out_of_memory = 2,
    failed_precondition = 3,
    visible_set_capacity_exceeded = 4,
};

pub const EngineConfig = extern struct {
    abi_version: u32 = ABI_VERSION,
    max_scene_rects: u32 = 0,
    max_visible_rects: u32 = 0,
    _reserved0: u32 = 0,
};

pub const EngineStats = extern struct {
    scene_rect_count: u32 = 0,
    visible_rect_count: u32 = 0,
    draw_rect_count: u32 = 0,
    last_status: EngineStatus = .ok,
};

comptime {
    std.debug.assert(@sizeOf(CameraUniform) == 32);
    std.debug.assert(@alignOf(CameraUniform) == 4);
    std.debug.assert(@offsetOf(CameraUniform, "transform") == 0);
    std.debug.assert(@offsetOf(CameraUniform, "viewport_width_px") == 24);
    std.debug.assert(@offsetOf(CameraUniform, "viewport_height_px") == 28);

    std.debug.assert(@sizeOf(Rect) == 32);
    std.debug.assert(@alignOf(Rect) == 4);
    std.debug.assert(@offsetOf(Rect, "color_rgba8") == 16);

    std.debug.assert(@sizeOf(EngineConfig) == 16);
    std.debug.assert(@sizeOf(EngineStats) == 16);
}

test "U10 camera_uniform_layout" {
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(CameraUniform));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(CameraUniform, "viewport_width_px"));
    try std.testing.expectEqual(@as(usize, 28), @offsetOf(CameraUniform, "viewport_height_px"));
}

test "U11 rect_layout" {
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(Rect));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(Rect, "color_rgba8"));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(Rect));
}
