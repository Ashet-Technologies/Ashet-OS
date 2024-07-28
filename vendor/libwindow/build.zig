const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libwindow_module = b.addModule("window", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    libwindow_module.linkSystemLibrary("c", .{});

    switch (target.result.os.tag) {
        .windows => {
            libwindow_module.linkSystemLibrary("User32", .{
                .needed = true,
                .preferred_link_mode = .static,
            });
        },
        else => {
            libwindow_module.linkSystemLibrary("xcb", .{
                .needed = true,
                .preferred_link_mode = .static,
            });
        },
    }

    const demo = b.addExecutable(.{
        .name = "libwindow-demo",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/demo.zig"),
    });
    demo.root_module.addImport("window", libwindow_module);
    b.installArtifact(demo);
}
