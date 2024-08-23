const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("ashet-std", .{
        .root_source_file = b.path("src/std.zig"),
    });

    const tests = b.addTest(.{
        .name = "ashet-std-tests",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/std.zig"),
    });

    b.installArtifact(tests);

    b.getInstallStep().dependOn(&b.addRunArtifact(tests).step);
}
