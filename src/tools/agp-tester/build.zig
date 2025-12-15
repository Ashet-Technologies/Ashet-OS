const std = @import("std");

pub fn build(b: *std.Build) void {
    const run_step = b.step("run", "Executes the AGP tester");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const abi_dep = b.dependency("abi", .{});
    const agp_dep = b.dependency("agp", .{});
    const agp_swrast_dep = b.dependency("agp_swrast", .{});
    const widgets_dep = b.dependency("widgets", .{
        .target = .x86,
    });

    const abi_mod = abi_dep.module("ashet-abi");
    const agp_mod = agp_dep.module("agp");
    const agp_swrast_mod = agp_swrast_dep.module("agp-swrast");
    const widgets_mod = widgets_dep.module("draw");

    const exe = b.addExecutable(.{
        .name = "agp-tester",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/agp-tester.zig"),
            .imports = &.{
                .{ .name = "agp", .module = agp_mod },
                .{ .name = "agp-swrast", .module = agp_swrast_mod },
                .{ .name = "abi", .module = abi_mod },
                .{ .name = "widgets-draw", .module = widgets_mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run_step.dependOn(&run.step);
}
