const std = @import("std");

pub fn build(b: *std.Build) void {
    const run_step = b.step("run", "Executes the AGP tester");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const suite_dep = b.dependency("agp_demosuite", .{ .target = target, .optimize = optimize });

    const exe = b.addExecutable(.{
        .name = "agp-tester",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/agp-tester.zig"),
            .imports = &.{
                .{ .name = "agp-demosuite", .module = suite_dep.module("agp-demosuite") },
            },
        }),
    });

    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run_step.dependOn(&run.step);
}
