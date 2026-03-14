const std = @import("std");
const root = @import("root.zig");

test "I06 engine_render_before_init_fails" {
    var engine: ?*root.Engine = null;
    const config = root.EngineConfig{
        .max_rects = 8,
        .max_visible_rects = 8,
        .initial_width_px = 320,
        .initial_height_px = 240,
    };
    try std.testing.expectEqual(root.EngineStatus.ok, root.ite_engine_create(&engine, &config));
    defer root.ite_engine_destroy(engine);

    try std.testing.expectEqual(root.EngineStatus.not_initialized, root.ite_engine_render(engine.?, null));
    try std.testing.expectEqualStrings(
        "render requires ite_engine_init first",
        std.mem.span(root.ite_engine_get_last_error(engine.?)),
    );
}
