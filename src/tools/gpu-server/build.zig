const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const abi_dep = b.dependency("abi", .{});
    const agp_dep = b.dependency("agp", .{});
    const agp_swrast_dep = b.dependency("agp_swrast", .{});

    const abi_mod = abi_dep.module("ashet-abi");
    const agp_mod = agp_dep.module("agp");
    const agp_swrast_mod = agp_swrast_dep.module("agp-swrast");

    const server_mod = b.createModule(.{
        .root_source_file = b.path("src/gpu-server.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "agp", .module = agp_mod },
            .{ .name = "agp-swrast", .module = agp_swrast_mod },
            .{ .name = "ashet", .module = abi_mod },
        },
    });

    const server_exe = b.addExecutable(.{
        .name = "gpu-server",
        .root_module = server_mod,
    });

    b.installArtifact(server_exe);
}
