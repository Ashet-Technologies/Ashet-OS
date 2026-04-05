const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const rast_mod = b.addModule("agp-tiled-rast", .{
        .root_source_file = b.path("src/tiled-raster.zig"),
        .target = target,
        .optimize = optimize,
    });

    const rast_exerciser = b.addExecutable(.{
        .name = "agp-tiled-rast-test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/exerciser.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
            .imports = &.{
                .{ .name = "agp-tiled-rast", .module = rast_mod },
            },
        }),
    });

    b.installArtifact(rast_exerciser);
}
