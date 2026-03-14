const std = @import("std");

const repo_root = ".";
const staged_metallib_path = "host/DemoApp/Resources/rect_fill.metallib";

test "I04 host_loads_metallib" {
    const allocator = std.testing.allocator;

    const metallib_stat = try std.fs.cwd().statFile(staged_metallib_path);
    try std.testing.expect(metallib_stat.size > 0);

    const swift_source = try std.fmt.allocPrint(allocator,
        \\import Foundation
        \\import Metal
        \\
        \\let url = URL(fileURLWithPath: "{s}")
        \\guard FileManager.default.fileExists(atPath: url.path) else {{
        \\    fputs("missing staged metallib at \\(url.path)\\n", stderr)
        \\    exit(1)
        \\}}
        \\
        \\guard let device = MTLCreateSystemDefaultDevice() else {{
        \\    fputs("unable to acquire Metal device\\n", stderr)
        \\    exit(1)
        \\}}
        \\
        \\let library = try device.makeLibrary(URL: url)
        \\let names = Set(library.functionNames)
        \\guard names.contains("rect_vertex") else {{
        \\    fputs("rect_vertex missing from metallib\\n", stderr)
        \\    exit(1)
        \\}}
        \\guard names.contains("rect_fragment") else {{
        \\    fputs("rect_fragment missing from metallib\\n", stderr)
        \\    exit(1)
        \\}}
        \\print("loaded \\(url.lastPathComponent)")
    , .{staged_metallib_path});
    defer allocator.free(swift_source);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "swift", "-e", swift_source },
        .cwd = repo_root,
        .max_output_bytes = 1024 * 1024,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("swift metallib load failed\nstdout:\n{s}\nstderr:\n{s}\n", .{
                    result.stdout,
                    result.stderr,
                });
                return error.UnexpectedExitCode;
            }
        },
        else => {
            std.debug.print("swift metallib load terminated abnormally\nstdout:\n{s}\nstderr:\n{s}\n", .{
                result.stdout,
                result.stderr,
            });
            return error.UnexpectedTermination;
        },
    }
}
