//! Shared ABI types used by Zig, C, Swift, and Metal code.

const std = @import("std");

/// Version tag embedded in the public engine header.
pub const ABI_VERSION: u32 = 1;

/// Camera transform uploaded once per frame.
pub const CameraUniform = extern struct {
    transform: [6]f32,
    viewport_width_px: u32,
    viewport_height_px: u32,
};

/// Rectangle instance payload shared with the CPU and GPU renderers.
pub const Rect = extern struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    color_rgba8: u32,
    _pad0: u32 = 0,
    _pad1: u32 = 0,
    _pad2: u32 = 0,
};

/// Status codes returned through the C ABI.
pub const EngineStatus = enum(c_int) {
    ok = 0,
    invalid_arg = 1,
    not_initialized = 2,
    io_error = 3,
    gpu_error = 4,
    capacity_exceeded = 5,
};

/// Static engine configuration chosen at creation time.
pub const EngineConfig = extern struct {
    pub const default_min_zoom: f32 = 1.0e-9;
    pub const default_max_zoom: f32 = 1.0e9;

    abi_version: u32 = ABI_VERSION,
    max_rects: u32,
    max_visible_rects: u32,
    initial_width_px: u32,
    initial_height_px: u32,
    min_zoom: f32 = default_min_zoom,
    max_zoom: f32 = default_max_zoom,
};

/// Frame diagnostics reported back to the host application.
pub const FrameStats = extern struct {
    total_rects: u32 = 0,
    visible_rects: u32 = 0,
    width_px: u32 = 0,
    height_px: u32 = 0,
};

comptime {
    std.debug.assert(@sizeOf(CameraUniform) == 32);
    std.debug.assert(@offsetOf(CameraUniform, "viewport_width_px") == 24);
    std.debug.assert(@offsetOf(CameraUniform, "viewport_height_px") == 28);
    std.debug.assert(@sizeOf(Rect) == 32);
    std.debug.assert(@offsetOf(Rect, "color_rgba8") == 16);
    std.debug.assert(@alignOf(Rect) == 4);
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
