const std = @import("std");
const c = @cImport({
    @cInclude("engine.h");
});

test "I06 engine_render_before_init_fails" {
    var engine: ?*c.ite_Engine = null;
    const config = c.ite_EngineConfig{
        .abi_version = c.ite_engine_header_version(),
        .max_scene_rects = 32,
        .max_visible_rects = 32,
        ._reserved0 = 0,
    };

    try std.testing.expectEqual(
        @as(c_uint, c.ite_EngineStatus_ok),
        @as(c_uint, c.ite_engine_create(&engine, &config)),
    );
    defer c.ite_engine_destroy(engine);

    const camera = c.ite_CameraUniform{
        .transform = .{ 1.0, 0.0, 0.0, 1.0, 0.0, 0.0 },
        .viewport_width_px = 800,
        .viewport_height_px = 600,
    };
    const rects = [_]c.ite_Rect{};

    try std.testing.expectEqual(
        @as(c_uint, c.ite_EngineStatus_failed_precondition),
        @as(c_uint, c.ite_engine_render(engine, &camera, &rects, 0, null)),
    );
    try std.testing.expectEqualStrings(
        "render requires ite_engine_init first",
        std.mem.span(c.ite_engine_get_last_error(engine)),
    );
}
