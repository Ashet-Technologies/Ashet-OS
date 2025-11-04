const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const elfstack_mod = b.addModule("elfstack", .{
        .root_source_file = b.path("elfstack.zig"),
        .target = target,
        .optimize = optimize,
    });

    const elfstack = b.addExecutable(.{
        .name = "elfstack",
        .root_module = elfstack_mod,
    });

    b.installArtifact(elfstack);
}
