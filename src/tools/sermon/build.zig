const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    const args_dep = b.dependency("args", .{});
    const serial_dep = b.dependency("serial", .{});

    const args_mod = args_dep.module("args");
    const serial_mod = serial_dep.module("serial");

    const sermon_mod = b.addModule("sermon", .{
        .root_source_file = b.path("sermon.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "args", .module = args_mod },
            .{ .name = "serial", .module = serial_mod },
        },
    });

    const sermon_exe = b.addExecutable(.{
        .name = "sermon",
        .root_module = sermon_mod,
    });

    b.installArtifact(sermon_exe);
}
