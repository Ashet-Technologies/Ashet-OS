const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const fast_mod = b.addModule("fast", .{
        .root_source_file = b.path("src/fast.zig"),
        .target = target,
        .optimize = optimize,
    });

    const fast_tests = b.addTest(.{
        .root_module = fast_mod,
    });

    const fast_test_run = b.addRunArtifact(fast_tests);

    b.getInstallStep().dependOn(&fast_test_run.step);
}
