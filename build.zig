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
    const shader_source = "src/shaders/rect_fill.metal";
    const shader_air_rel = "shaders/rect_fill.air";
    const shader_metallib_rel = "shaders/rect_fill.metallib";
    const shader_stage_rel = "host/DemoApp/Resources/rect_fill.metallib";

    const doctor_cmd = [_][]const u8{"scripts/doctor.sh"};
    const fmt_cmd = [_][]const u8{"scripts/fmt.sh"};
    const unit_cmd = [_][]const u8{"scripts/test-unit.sh"};
    const integration_cmd = [_][]const u8{"scripts/test-integration-cpu.sh"};
    const gpu_cmd = [_][]const u8{"scripts/test-gpu.sh"};
    const host_cmd = [_][]const u8{"scripts/build-host.sh"};
    const ci_cmd = [_][]const u8{"scripts/verify-commit.sh"};

    const doctor_step = addShellStep(b, "doctor", "Validate pinned toolchain and required Apple tools", &doctor_cmd);
    const fmt_step = addShellStep(b, "fmt", "Run formatting checks", &fmt_cmd);
    const unit_step = addShellStep(b, "test-unit", "Run pure Zig unit tests", &unit_cmd);

    const metal_compile = b.addSystemCommand(&.{ "xcrun", "metal", "-c" });
    metal_compile.setName("metal compile rect_fill.metal");
    metal_compile.addFileArg(b.path(shader_source));
    metal_compile.addArg("-o");
    const shader_air = metal_compile.addOutputFileArg("rect_fill.air");
    const install_shader_air = b.addInstallFile(shader_air, shader_air_rel);

    const shader_air_step = b.step("shader-air", "Compile src/shaders/rect_fill.metal to AIR");
    shader_air_step.dependOn(&install_shader_air.step);

    const metallib_link = b.addSystemCommand(&.{ "xcrun", "metallib" });
    metallib_link.setName("metallib rect_fill.air");
    metallib_link.addFileArg(shader_air);
    metallib_link.addArg("-o");
    const shader_metallib = metallib_link.addOutputFileArg("rect_fill.metallib");
    const install_shader_metallib = b.addInstallFile(shader_metallib, shader_metallib_rel);

    const shader_metallib_step = b.step("shader-metallib", "Link AIR into zig-out/shaders/rect_fill.metallib");
    shader_metallib_step.dependOn(&install_shader_metallib.step);

    const stage_shader_dir = b.addSystemCommand(&.{ "mkdir", "-p", "host/DemoApp/Resources" });
    stage_shader_dir.setName("mkdir host/DemoApp/Resources");
    stage_shader_dir.has_side_effects = true;

    const staged_metallib_input: std.Build.LazyPath = .{
        .cwd_relative = b.getInstallPath(.prefix, shader_metallib_rel),
    };
    const stage_shader = b.addSystemCommand(&.{"cp"});
    stage_shader.setName("stage rect_fill.metallib");
    stage_shader.addFileArg(staged_metallib_input);
    stage_shader.addArg(shader_stage_rel);
    stage_shader.has_side_effects = true;
    stage_shader.step.dependOn(&stage_shader_dir.step);
    stage_shader.step.dependOn(&install_shader_metallib.step);

    const shader_step = b.step("shader", "Build the Metal shader and stage the metallib");
    shader_step.dependOn(&stage_shader.step);

    const integration_step = addShellStep(b, "test-integration-cpu", "Run ABI and CPU integration tests", &integration_cmd);
    const gpu_step = addShellStep(b, "test-gpu", "Run headless GPU smoke tests", &gpu_cmd);
    gpu_step.dependOn(shader_step);

    const host_step = addShellStep(b, "host", "Build the macOS host app", &host_cmd);
    host_step.dependOn(shader_step);

    _ = doctor_step;
    _ = fmt_step;
    _ = unit_step;
    _ = integration_step;

    _ = addShellStep(b, "ci", "Run the canonical commit verification suite", &ci_cmd);
}
