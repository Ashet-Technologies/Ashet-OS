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

    b.installArtifact(exe);
}
