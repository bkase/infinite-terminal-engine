const std = @import("std");

const shader_source = "src/shaders/rect_fill.metal";
const staged_metallib_path = "host/DemoApp/Resources/rect_fill.metallib";

fn expectCommandOk(allocator: std.mem.Allocator, argv: []const []const u8) !void {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .cwd = ".",
        .max_output_bytes = 1024 * 1024,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| if (code != 0) {
            std.debug.print("command failed: {s}\nstdout:\n{s}\nstderr:\n{s}\n", .{
                argv[0],
                result.stdout,
                result.stderr,
            });
            return error.UnexpectedExitCode;
        },
        else => return error.UnexpectedTermination,
    }
}

test "I01 metal_compile_smoke" {
    const allocator = std.testing.allocator;
    try expectCommandOk(allocator, &.{ "scripts/build-shader.sh", "air" });
    const air_stat = try std.fs.cwd().statFile("zig-out/shaders/rect_fill.air");
    try std.testing.expect(air_stat.size > 0);
}

test "I02 metallib_build" {
    const allocator = std.testing.allocator;
    try expectCommandOk(allocator, &.{ "scripts/build-shader.sh", "metallib" });
    const metallib_stat = try std.fs.cwd().statFile("zig-out/shaders/rect_fill.metallib");
    try std.testing.expect(metallib_stat.size > 0);
}

test "I04 host_loads_metallib" {
    const allocator = std.testing.allocator;
    try expectCommandOk(allocator, &.{ "scripts/build-shader.sh", "stage" });
    const metallib_stat = try std.fs.cwd().statFile(staged_metallib_path);
    try std.testing.expect(metallib_stat.size > 0);

    const swift_source = try std.fmt.allocPrint(
        allocator,
        \\import Foundation
        \\import Metal
        \\let path = "{s}"
        \\guard FileManager.default.fileExists(atPath: path) else {{ fatalError("missing metallib") }}
        \\guard let device = MTLCreateSystemDefaultDevice() else {{ fatalError("missing device") }}
        \\let library = try device.makeLibrary(URL: URL(fileURLWithPath: path))
        \\let names = Set(library.functionNames)
        \\guard names.contains("rect_vertex") && names.contains("rect_fragment") else {{ fatalError("missing shader entrypoints") }}
        \\print("ok")
    ,
        .{staged_metallib_path},
    );
    defer allocator.free(swift_source);

    try expectCommandOk(allocator, &.{ "swift", "-e", swift_source });

    _ = shader_source;
}
