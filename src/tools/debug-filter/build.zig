const std = @import("std");

pub fn build(b: *std.Build) !void {
    const test_step = b.step("test", "runs the tests");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const args_mod = b.dependency("args", .{}).module("args");

    const debugfilter_mod = b.addModule("debug-filter", .{
        .root_source_file = b.path("debug-filter.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "args", .module = args_mod },
        },
    });
    debugfilter_mod.linkSystemLibrary("unwind", .{});

    const exe = b.addExecutable(.{
        .name = "debug-filter",
        .root_module = debugfilter_mod,
    });

    b.installArtifact(exe);

    const app_test = b.addTest(.{ .root_module = debugfilter_mod });

    const run_app_test = b.addRunArtifact(app_test);
    test_step.dependOn(&run_app_test.step);
}
