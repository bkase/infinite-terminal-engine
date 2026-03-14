//! Camera math shared by the CPU and GPU render paths.

const std = @import("std");
const abi = @import("../shared/abi.zig");

/// 2D point in either canvas or screen space.
pub const Point = struct {
    x: f32,
    y: f32,
};

/// Canvas-space bounds visible through the current camera.
pub const ViewBounds = struct {
    min_x: f32,
    min_y: f32,
    max_x: f32,
    max_y: f32,
};

/// Mutable camera state stored by the engine.
pub const Camera = struct {
    pan_x: f32 = 0,
    pan_y: f32 = 0,
    zoom: f32 = 1,
    min_zoom: f32 = 0.125,
    max_zoom: f32 = 8,
    width_px: u32,
    height_px: u32,

    pub fn init(width_px: u32, height_px: u32, min_zoom: f32, max_zoom: f32) Camera {
        return .{
            .width_px = width_px,
            .height_px = height_px,
            .min_zoom = min_zoom,
            .max_zoom = max_zoom,
        };
    }

    pub fn resize(self: *Camera, width_px: u32, height_px: u32) void {
        self.width_px = width_px;
        self.height_px = height_px;
    }

    pub fn pan(self: *Camera, delta_x_px: f32, delta_y_px: f32) void {
        self.pan_x -= delta_x_px / self.zoom;
        self.pan_y -= delta_y_px / self.zoom;
    }

    pub fn zoomBy(self: *Camera, delta: f32, anchor_x_px: f32, anchor_y_px: f32) void {
        const before = self.screenToCanvas(anchor_x_px, anchor_y_px);
        const unclamped = self.zoom * delta;
        self.zoom = std.math.clamp(unclamped, self.min_zoom, self.max_zoom);
        const after = self.screenToCanvas(anchor_x_px, anchor_y_px);
        self.pan_x += before.x - after.x;
        self.pan_y += before.y - after.y;
    }

    pub fn canvasToScreen(self: Camera, canvas_x: f32, canvas_y: f32) Point {
        return .{
            .x = (canvas_x - self.pan_x) * self.zoom,
            .y = (canvas_y - self.pan_y) * self.zoom,
        };
    }

    pub fn screenToCanvas(self: Camera, screen_x: f32, screen_y: f32) Point {
        return .{
            .x = screen_x / self.zoom + self.pan_x,
            .y = screen_y / self.zoom + self.pan_y,
        };
    }

    pub fn viewBounds(self: Camera) ViewBounds {
        const top_left = self.screenToCanvas(0, 0);
        const bottom_right = self.screenToCanvas(@floatFromInt(self.width_px), @floatFromInt(self.height_px));
        return .{
            .min_x = top_left.x,
            .min_y = top_left.y,
            .max_x = bottom_right.x,
            .max_y = bottom_right.y,
        };
    }

    pub fn uniform(self: Camera) abi.CameraUniform {
        return .{
            .transform = .{
                self.zoom,
                0,
                0,
                self.zoom,
                -self.pan_x * self.zoom,
                -self.pan_y * self.zoom,
            },
            .viewport_width_px = self.width_px,
            .viewport_height_px = self.height_px,
        };
    }
};

test "U01 camera_roundtrip" {
    var camera = Camera.init(800, 600, 0.125, 8);
    camera.pan(40, 20);
    camera.zoomBy(1.5, 200, 150);
    const canvas = camera.screenToCanvas(320, 240);
    const screen = camera.canvasToScreen(canvas.x, canvas.y);
    try std.testing.expectApproxEqAbs(@as(f32, 320), screen.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 240), screen.y, 0.001);
}

test "U02 zoom_anchor_preserved" {
    var camera = Camera.init(800, 600, 0.125, 8);
    const before = camera.screenToCanvas(250, 140);
    camera.zoomBy(2, 250, 140);
    const after = camera.screenToCanvas(250, 140);
    try std.testing.expectApproxEqAbs(before.x, after.x, 0.001);
    try std.testing.expectApproxEqAbs(before.y, after.y, 0.001);
}

test "U03 zoom_clamped" {
    var camera = Camera.init(800, 600, 0.5, 2);
    camera.zoomBy(100, 0, 0);
    try std.testing.expectEqual(@as(f32, 2), camera.zoom);
    camera.zoomBy(0.001, 0, 0);
    try std.testing.expectEqual(@as(f32, 0.5), camera.zoom);
}

test "U04 pan_updates_camera" {
    var camera = Camera.init(800, 600, 0.125, 8);
    camera.pan(40, -20);
    try std.testing.expectEqual(@as(f32, -40), camera.pan_x);
    try std.testing.expectEqual(@as(f32, 20), camera.pan_y);
}

test "U18 camera_snapshot_isolation" {
    var camera = Camera.init(800, 600, 0.125, 8);
    const snapshot = camera.uniform();
    camera.pan(40, 20);
    try std.testing.expectEqual(@as(f32, 0), snapshot.transform[4]);
    try std.testing.expectEqual(@as(f32, 0), snapshot.transform[5]);
}
