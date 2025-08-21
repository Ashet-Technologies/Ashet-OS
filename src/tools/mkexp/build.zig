const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    const args_mod = b.dependency("args", .{}).module("args");

    const mkfont_exe = b.addExecutable(.{
        .name = "mkexp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/mkexp.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "args", .module = args_mod },
            },
        }),
    });

    b.installArtifact(mkfont_exe);
}
