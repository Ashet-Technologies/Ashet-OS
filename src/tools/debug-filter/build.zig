const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "debug-filter",
        .root_source_file = b.path("debug-filter.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const args_mod = b.dependency("args", .{}).module("args");
    exe.root_module.addImport("args", args_mod);

    b.installArtifact(exe);
}
