const std = @import("std");

const repo_root = ".";
const shader_source = "src/shaders/rect_fill.metal";

fn expectCommandOk(allocator: std.mem.Allocator, argv: []const []const u8) !void {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .cwd = repo_root,
        .max_output_bytes = 1024 * 1024,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("command failed: {s}\nstdout:\n{s}\nstderr:\n{s}\n", .{
                    argv[0],
                    result.stdout,
                    result.stderr,
                });
                return error.UnexpectedExitCode;
            }
        },
        else => {
            std.debug.print("command terminated abnormally: {s}\nstdout:\n{s}\nstderr:\n{s}\n", .{
                argv[0],
                result.stdout,
                result.stderr,
            });
            return error.UnexpectedTermination;
        },
    }
}

fn tmpPath(
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,
    basename: []const u8,
) ![]u8 {
    return std.fs.path.resolve(allocator, &.{
        ".zig-cache",
        "tmp",
        tmp_dir.sub_path[0..],
        basename,
    });
}

test "I01 metal_compile_smoke" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const air_path = try tmpPath(allocator, tmp_dir, "rect_fill.air");
    defer allocator.free(air_path);

    try expectCommandOk(allocator, &.{
        "xcrun",
        "metal",
        "-c",
        shader_source,
        "-o",
        air_path,
    });

    const air_stat = try std.fs.cwd().statFile(air_path);
    try std.testing.expect(air_stat.size > 0);
}

test "I02 metallib_build" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const air_path = try tmpPath(allocator, tmp_dir, "rect_fill.air");
    defer allocator.free(air_path);

    const metallib_path = try tmpPath(allocator, tmp_dir, "rect_fill.metallib");
    defer allocator.free(metallib_path);

    try expectCommandOk(allocator, &.{
        "xcrun",
        "metal",
        "-c",
        shader_source,
        "-o",
        air_path,
    });
    try expectCommandOk(allocator, &.{
        "xcrun",
        "metallib",
        air_path,
        "-o",
        metallib_path,
    });

    const metallib_stat = try std.fs.cwd().statFile(metallib_path);
    try std.testing.expect(metallib_stat.size > 0);
}
