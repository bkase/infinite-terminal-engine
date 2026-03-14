const std = @import("std");
const abi = @import("abi.zig");

pub const Vec2 = struct {
    x: f32,
    y: f32,
};

pub const Affine2 = struct {
    m00: f32,
    m01: f32,
    m10: f32,
    m11: f32,
    tx: f32,
    ty: f32,

    pub fn identity() Affine2 {
        return .{
            .m00 = 1.0,
            .m01 = 0.0,
            .m10 = 0.0,
            .m11 = 1.0,
            .tx = 0.0,
            .ty = 0.0,
        };
    }

    pub fn translation(offset: Vec2) Affine2 {
        var transform = identity();
        transform.tx = offset.x;
        transform.ty = offset.y;
        return transform;
    }

    pub fn scaleUniform(value: f32) Affine2 {
        return .{
            .m00 = value,
            .m01 = 0.0,
            .m10 = 0.0,
            .m11 = value,
            .tx = 0.0,
            .ty = 0.0,
        };
    }

    pub fn multiply(lhs: Affine2, rhs: Affine2) Affine2 {
        return .{
            .m00 = lhs.m00 * rhs.m00 + lhs.m01 * rhs.m10,
            .m01 = lhs.m00 * rhs.m01 + lhs.m01 * rhs.m11,
            .m10 = lhs.m10 * rhs.m00 + lhs.m11 * rhs.m10,
            .m11 = lhs.m10 * rhs.m01 + lhs.m11 * rhs.m11,
            .tx = lhs.m00 * rhs.tx + lhs.m01 * rhs.ty + lhs.tx,
            .ty = lhs.m10 * rhs.tx + lhs.m11 * rhs.ty + lhs.ty,
        };
    }

    pub fn apply(self: Affine2, point: Vec2) Vec2 {
        return .{
            .x = self.m00 * point.x + self.m01 * point.y + self.tx,
            .y = self.m10 * point.x + self.m11 * point.y + self.ty,
        };
    }

    pub fn inverse(self: Affine2) Affine2 {
        const det = self.m00 * self.m11 - self.m01 * self.m10;
        std.debug.assert(det != 0.0);

        const inv_det = 1.0 / det;
        return .{
            .m00 = self.m11 * inv_det,
            .m01 = -self.m01 * inv_det,
            .m10 = -self.m10 * inv_det,
            .m11 = self.m00 * inv_det,
            .tx = (self.m01 * self.ty - self.m11 * self.tx) * inv_det,
            .ty = (self.m10 * self.tx - self.m00 * self.ty) * inv_det,
        };
    }
};

pub const Camera = struct {
    viewport_width_px: u32,
    viewport_height_px: u32,
    min_zoom: f32,
    max_zoom: f32,
    canvas_to_screen: Affine2,
    screen_to_canvas: Affine2,

    pub fn init(viewport_width_px: u32, viewport_height_px: u32) Camera {
        const identity = Affine2.identity();
        return .{
            .viewport_width_px = viewport_width_px,
            .viewport_height_px = viewport_height_px,
            .min_zoom = 0.25,
            .max_zoom = 8.0,
            .canvas_to_screen = identity,
            .screen_to_canvas = identity,
        };
    }

    pub fn withZoomLimits(self: Camera, min_zoom: f32, max_zoom: f32) Camera {
        var camera = self;
        camera.min_zoom = min_zoom;
        camera.max_zoom = max_zoom;
        camera.clampZoomInPlace();
        return camera;
    }

    pub fn currentZoom(self: Camera) f32 {
        return self.canvas_to_screen.m00;
    }

    pub fn panByScreenDelta(self: *Camera, delta: Vec2) void {
        self.canvas_to_screen = Affine2.multiply(Affine2.translation(delta), self.canvas_to_screen);
        self.refreshInverse();
    }

    pub fn zoomAroundScreenPoint(self: *Camera, anchor: Vec2, factor: f32) void {
        const old_zoom = self.currentZoom();
        const requested_zoom = old_zoom * factor;
        const clamped_zoom = std.math.clamp(requested_zoom, self.min_zoom, self.max_zoom);
        const ratio = clamped_zoom / old_zoom;

        self.canvas_to_screen = Affine2.multiply(
            Affine2.translation(anchor),
            Affine2.multiply(
                Affine2.scaleUniform(ratio),
                Affine2.multiply(Affine2.translation(.{ .x = -anchor.x, .y = -anchor.y }), self.canvas_to_screen),
            ),
        );
        self.refreshInverse();
    }

    pub fn screenToCanvas(self: Camera, point: Vec2) Vec2 {
        return self.screen_to_canvas.apply(point);
    }

    pub fn canvasToScreen(self: Camera, point: Vec2) Vec2 {
        return self.canvas_to_screen.apply(point);
    }

    pub fn viewportCanvasRect(self: Camera) abi.Rect {
        const top_left = self.screenToCanvas(.{ .x = 0.0, .y = 0.0 });
        const bottom_right = self.screenToCanvas(.{
            .x = @floatFromInt(self.viewport_width_px),
            .y = @floatFromInt(self.viewport_height_px),
        });

        return .{
            .x = top_left.x,
            .y = top_left.y,
            .width = bottom_right.x - top_left.x,
            .height = bottom_right.y - top_left.y,
            .color_rgba8 = 0,
        };
    }

    pub fn toUniform(self: Camera) abi.CameraUniform {
        return .{
            .transform = .{
                self.canvas_to_screen.m00,
                self.canvas_to_screen.m10,
                self.canvas_to_screen.m01,
                self.canvas_to_screen.m11,
                self.canvas_to_screen.tx,
                self.canvas_to_screen.ty,
            },
            .viewport_width_px = self.viewport_width_px,
            .viewport_height_px = self.viewport_height_px,
        };
    }

    fn clampZoomInPlace(self: *Camera) void {
        const zoom = std.math.clamp(self.currentZoom(), self.min_zoom, self.max_zoom);
        self.canvas_to_screen.m00 = zoom;
        self.canvas_to_screen.m11 = zoom;
        self.refreshInverse();
    }

    fn refreshInverse(self: *Camera) void {
        self.screen_to_canvas = self.canvas_to_screen.inverse();
    }
};

fn expectNear(actual: f32, expected: f32) !void {
    try std.testing.expectApproxEqAbs(expected, actual, 0.0001);
}

test "U01 camera_roundtrip" {
    var camera = Camera.init(800, 600);
    camera.panByScreenDelta(.{ .x = 32.0, .y = -12.0 });
    camera.zoomAroundScreenPoint(.{ .x = 200.0, .y = 150.0 }, 1.5);

    const canvas_point = camera.screenToCanvas(.{ .x = 123.0, .y = 456.0 });
    const screen_point = camera.canvasToScreen(canvas_point);

    try expectNear(screen_point.x, 123.0);
    try expectNear(screen_point.y, 456.0);
}

test "U02 zoom_anchor_preserved" {
    var camera = Camera.init(1024, 768);
    const anchor = Vec2{ .x = 320.0, .y = 240.0 };
    const before = camera.screenToCanvas(anchor);

    camera.zoomAroundScreenPoint(anchor, 2.0);

    const after = camera.screenToCanvas(anchor);
    try expectNear(after.x, before.x);
    try expectNear(after.y, before.y);
}

test "U03 zoom_clamped" {
    var camera = Camera.init(640, 480).withZoomLimits(0.5, 2.0);

    camera.zoomAroundScreenPoint(.{ .x = 100.0, .y = 100.0 }, 10.0);
    try expectNear(camera.currentZoom(), 2.0);

    camera.zoomAroundScreenPoint(.{ .x = 100.0, .y = 100.0 }, 0.01);
    try expectNear(camera.currentZoom(), 0.5);
}

test "U04 pan_updates_camera" {
    var camera = Camera.init(640, 480);
    camera.panByScreenDelta(.{ .x = 25.0, .y = 10.0 });

    const top_left = camera.screenToCanvas(.{ .x = 0.0, .y = 0.0 });
    try expectNear(top_left.x, -25.0);
    try expectNear(top_left.y, -10.0);

    const uniform = camera.toUniform();
    try expectNear(uniform.transform[4], 25.0);
    try expectNear(uniform.transform[5], 10.0);
}
