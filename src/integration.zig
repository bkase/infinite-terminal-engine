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

test "I07 frame_stats_update_after_render_prep" {
    var engine: ?*root.Engine = null;
    const config = root.EngineConfig{
        .max_rects = 8,
        .max_visible_rects = 8,
        .initial_width_px = 100,
        .initial_height_px = 80,
    };
    try std.testing.expectEqual(root.EngineStatus.ok, root.ite_engine_create(&engine, &config));
    defer root.ite_engine_destroy(engine);

    const rects = [_]root.Rect{
        .{ .x = 0, .y = 0, .w = 10, .h = 10, .color_rgba8 = 1 },
        .{ .x = 200, .y = 200, .w = 10, .h = 10, .color_rgba8 = 2 },
    };
    try std.testing.expectEqual(root.EngineStatus.ok, root.ite_engine_replace_rects(engine.?, &rects, rects.len));
    try std.testing.expectEqual(root.EngineStatus.invalid_arg, root.ite_engine_init(engine.?, null, null, null));

    var stats: root.FrameStats = .{};
    try std.testing.expectEqual(root.EngineStatus.ok, root.ite_engine_get_stats(engine.?, &stats));
    try std.testing.expectEqual(@as(u32, 100), stats.width_px);
    try std.testing.expectEqual(@as(u32, 80), stats.height_px);
}
