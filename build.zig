const std = @import("std");

fn addShellStep(
    b: *std.Build,
    name: []const u8,
    description: []const u8,
    argv: []const []const u8,
) *std.Build.Step {
    const step = b.step(name, description);
    const run = b.addSystemCommand(argv);
    run.has_side_effects = true;
    step.dependOn(&run.step);
    return step;
}

pub fn build(b: *std.Build) void {
    const doctor_cmd = [_][]const u8{"scripts/doctor.sh"};
    const fmt_cmd = [_][]const u8{"scripts/fmt.sh"};
    const unit_cmd = [_][]const u8{"scripts/test-unit.sh"};
    const shader_air_cmd = [_][]const u8{ "scripts/build-shader.sh", "air" };
    const shader_metallib_cmd = [_][]const u8{ "scripts/build-shader.sh", "metallib" };
    const shader_cmd = [_][]const u8{ "scripts/build-shader.sh", "stage" };
    const integration_cmd = [_][]const u8{"scripts/test-integration-cpu.sh"};
    const gpu_cmd = [_][]const u8{"scripts/test-gpu.sh"};
    const host_cmd = [_][]const u8{"scripts/build-host.sh"};
    const ghostty_wrapper_cmd = [_][]const u8{"scripts/test-ghostty-wrapper.sh"};
    const ci_cmd = [_][]const u8{"scripts/verify-commit.sh"};

    _ = addShellStep(b, "doctor", "Validate pinned toolchain and required Apple tools", &doctor_cmd);
    _ = addShellStep(b, "fmt", "Run formatting checks", &fmt_cmd);
    _ = addShellStep(b, "test-unit", "Run pure Zig unit tests", &unit_cmd);
    const shader_air = addShellStep(b, "shader-air", "Compile the Metal shader to AIR", &shader_air_cmd);
    const shader_metallib = addShellStep(b, "shader-metallib", "Link the shader AIR into a metallib", &shader_metallib_cmd);
    shader_metallib.dependOn(shader_air);
    const shader = addShellStep(b, "shader", "Stage the metallib into host resources", &shader_cmd);
    shader.dependOn(shader_metallib);
    _ = addShellStep(b, "test-integration-cpu", "Run ABI and CPU integration tests", &integration_cmd);
    const gpu = addShellStep(b, "test-gpu", "Run headless GPU smoke tests", &gpu_cmd);
    gpu.dependOn(shader);
    const host = addShellStep(b, "host", "Build the macOS host app", &host_cmd);
    host.dependOn(shader);
    _ = addShellStep(b, "test-ghostty-wrapper", "Run the pinned Ghostty wrapper compatibility checks", &ghostty_wrapper_cmd);
    _ = addShellStep(b, "ci", "Run the canonical commit verification suite", &ci_cmd);
}
