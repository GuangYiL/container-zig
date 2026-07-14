const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdk_module = b.addModule("container_zig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const demo = b.addExecutable(.{
        .name = "container-zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    demo.root_module.addImport("container_zig", sdk_module);
    b.installArtifact(demo);

    const run_step = b.step("run", "Run the app");
    const run_demo = b.addRunArtifact(demo);
    run_step.dependOn(&run_demo.step);
    run_demo.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_demo.addArgs(args);
    }

    const sdk_module_tests = b.addTest(.{
        .root_module = sdk_module,
    });
    const run_sdk_module_tests = b.addRunArtifact(sdk_module_tests);

    const demo_tests = b.addTest(.{
        .root_module = demo.root_module,
    });
    const run_demo_tests = b.addRunArtifact(demo_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_sdk_module_tests.step);
    test_step.dependOn(&run_demo_tests.step);
}
