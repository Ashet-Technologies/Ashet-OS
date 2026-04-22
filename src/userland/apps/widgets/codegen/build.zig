const std = @import("std");

pub fn build(b: *std.Build) void {
    const libgui_dep = b.dependency("libgui", .{});

    const exe = b.addExecutable(.{
        .name = "widgets-codegen",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .root_source_file = b.path("src/widgets-codegen.zig"),
            .imports = &.{
                .{ .name = "widget-def-model", .module = libgui_dep.module("widgets-model") },
            },
        }),
    });

    b.installArtifact(exe);
}
