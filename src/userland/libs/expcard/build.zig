const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    const expcard_mod = b.addModule("expcard", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/expcard.zig"),
    });

    const tests_exe = b.addTest(.{ .root_module = expcard_mod });

    const run_tests = b.addRunArtifact(tests_exe);

    b.getInstallStep().dependOn(&run_tests.step);
}
