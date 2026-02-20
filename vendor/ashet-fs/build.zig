const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    const args_dep = b.dependency("args", .{});
    const args_mod = args_dep.module("args");

    const afs_mod = b.addModule("ashet-fs", .{
        .root_source_file = b.path("src/afs.zig"),
    });

    const afs_tool_mod = b.createModule(.{
        .root_source_file = b.path("src/afs-tool.zig"),
        .target = target,
        .optimize = optimize,
    });
    const afs_tool = b.addExecutable(.{
        .name = "afs-tool",
        .root_module = afs_tool_mod,
    });
    afs_tool.root_module.addImport("afs", afs_mod);
    afs_tool.root_module.addImport("args", args_mod);
    b.installArtifact(afs_tool);

    const afs_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/testsuite.zig"),
            .target = target,
            .imports = &.{
                .{ .name = "afs", .module = afs_mod },
            },
        }),
    });
    const afs_test_run = b.addRunArtifact(afs_test);
    const test_step = b.step("test", "Run the testsuite");
    test_step.dependOn(&afs_test_run.step);
}
