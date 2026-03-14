const std = @import("std");

fn addShellStep(
    b: *std.Build,
    name: []const u8,
    description: []const u8,
    argv: []const []const u8,
) void {
    const step = b.step(name, description);
    const run = b.addSystemCommand(argv);
    run.has_side_effects = true;
    step.dependOn(&run.step);
}

pub fn build(b: *std.Build) void {
    const doctor_cmd = [_][]const u8{"scripts/doctor.sh"};
    const fmt_cmd = [_][]const u8{"scripts/fmt.sh"};
    const unit_cmd = [_][]const u8{"scripts/test-unit.sh"};
    const shader_cmd = [_][]const u8{"scripts/build-shader.sh"};
    const integration_cmd = [_][]const u8{"scripts/test-integration-cpu.sh"};
    const gpu_cmd = [_][]const u8{"scripts/test-gpu.sh"};
    const host_cmd = [_][]const u8{"scripts/build-host.sh"};
    const ci_cmd = [_][]const u8{"scripts/verify-commit.sh"};

    addShellStep(b, "doctor", "Validate pinned toolchain and required Apple tools", &doctor_cmd);
    addShellStep(b, "fmt", "Run formatting checks", &fmt_cmd);
    addShellStep(b, "test-unit", "Run pure Zig unit tests", &unit_cmd);
    addShellStep(b, "shader", "Build the Metal shader and stage the metallib", &shader_cmd);
    addShellStep(b, "test-integration-cpu", "Run ABI and CPU integration tests", &integration_cmd);
    addShellStep(b, "test-gpu", "Run headless GPU smoke tests", &gpu_cmd);
    addShellStep(b, "host", "Build the macOS host app", &host_cmd);
    addShellStep(b, "ci", "Run the canonical commit verification suite", &ci_cmd);
}
