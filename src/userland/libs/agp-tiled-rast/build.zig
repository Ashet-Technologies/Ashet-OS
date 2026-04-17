const std = @import("std");

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Runs the test suite");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const abi_dep = b.dependency("abi", .{});
    const agp_dep = b.dependency("agp", .{});
    const agp_swrast_dep = b.dependency("agp_swrast", .{});
    const turtlefont_dep = b.dependency("turtlefont", .{});

    const abi_mod = abi_dep.module("ashet-abi");
    const agp_mod = agp_dep.module("agp");
    const agp_swrast_mod = agp_swrast_dep.module("agp-swrast");
    const turtlefont_mod = turtlefont_dep.module("turtlefont");

    const rast_mod = b.addModule("agp-tiled-rast", .{
        .root_source_file = b.path("src/tiled-raster.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "ashet-abi", .module = abi_mod },
            .{ .name = "agp", .module = agp_mod },
            .{ .name = "turtlefont", .module = turtlefont_mod },
            .{ .name = "agp-swrast", .module = agp_swrast_mod }, // TODO: Delete this and factor common parts into a common code
        },
    });

    // exerciser tests:

    const rast_exerciser = b.addExecutable(.{
        .name = "agp-tiled-rast-test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/exerciser.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ashet-abi", .module = abi_mod },
                .{ .name = "agp", .module = agp_mod },
                .{ .name = "agp-tiled-rast", .module = rast_mod },
                .{ .name = "agp-swrast", .module = agp_swrast_mod },
            },
        }),
    });
    b.installArtifact(rast_exerciser);

    const exerciser_run = b.addRunArtifact(rast_exerciser);
    if (b.args) |args| {
        exerciser_run.addArgs(args);
    }
    test_step.dependOn(&exerciser_run.step);

    const exerciser_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/exerciser.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ashet-abi", .module = abi_mod },
                .{ .name = "agp", .module = agp_mod },
                .{ .name = "agp-tiled-rast", .module = rast_mod },
                .{ .name = "agp-swrast", .module = agp_swrast_mod },
            },
        }),
    });

    const exerciser_test_run = b.addRunArtifact(exerciser_tests);
    test_step.dependOn(&exerciser_test_run.step);

    // regular unit tests:

    const rast_tests = b.addTest(.{
        .root_module = rast_mod,
    });

    const test_run = b.addRunArtifact(rast_tests);
    test_step.dependOn(&test_run.step);
}
