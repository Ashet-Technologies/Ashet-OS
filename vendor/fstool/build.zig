const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    const args_dep = b.dependency("args", .{});
    const args_mod = args_dep.module("args");

    const exe = b.addExecutable(.{
        .name = "fs",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/fstool.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "args", .module = args_mod },
            },
        }),
    });

    b.installArtifact(exe);
}
