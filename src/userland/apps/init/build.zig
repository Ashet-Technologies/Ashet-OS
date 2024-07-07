const std = @import("std");
const AshetOS = @import("AshetOS");

pub fn build(b: *std.Build) void {
    const target = AshetOS.standardTargetOption(b);
    const optimize = b.standardOptimizeOption(.{});

    const ashet_dep = b.dependency("AshetOS", .{ .target = target });

    const ashet_lib = ashet_dep.artifact("AshetOS");
    const ashet_mod = ashet_dep.module("ashet");

    const exe = AshetOS.addExecutable(b, .{
        .name = "init",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("init.zig"),
    });

    // Not mandatory, but really really sensible:
    exe.linkLibrary(ashet_lib);
    exe.root_module.addImport("ashet", ashet_mod);

    // Same for all applications:
    exe.setLinkerScript(ashet_dep.path("application.ld"));

    b.installArtifact(exe);
}
