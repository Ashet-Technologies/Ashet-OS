const std = @import("std");

pub fn build(b: *std.Build) void {
    const run_step = b.step("run", "Executes the AGP tester");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const agp_dep = b.dependency("agp", .{});

    const agp_mod = agp_dep.module("agp");

    const exe = b.addExecutable(.{
        .name = "agp-tester",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/agp-tester.zig"),
    });

    exe.root_module.addImport("agp", agp_mod);

    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run_step.dependOn(&run.step);
}
