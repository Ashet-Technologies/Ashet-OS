const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    const args_dep = b.dependency("args", .{});
    const args_mod = args_dep.module("args");

    const afs_mod = b.addModule("ashet-fs", .{
        .root_source_file = b.path("src/afs.zig"),
    });

    const afs_tool = b.addExecutable(.{
        .name = "afs-tool",
        .root_source_file = b.path("src/afs-tool.zig"),
        .target = target,
        .optimize = optimize,
    });
    afs_tool.root_module.addImport("afs", afs_mod);
    afs_tool.root_module.addImport("args", args_mod);
    b.installArtifact(afs_tool);
}
