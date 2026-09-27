const std = @import("std");

pub fn build(b: *std.Build) void {
    const abi = b.dependency("abi", .{}).module("ashet-abi");
    const agp = b.dependency("agp", .{}).module("agp");
    const swrast = b.dependency("agp_swrast", .{}).module("agp-swrast");

    const mod = b.addModule("agp-demosuite", .{
        .root_source_file = b.path("src/agp-demosuite.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    });
    mod.addImport("ashet-abi", abi);
    mod.addImport("agp", agp);
    mod.addImport("agp-swrast", swrast);

    const tests = b.addTest(.{ .root_module = mod });
    b.step("test", "Test AGP demosuite").dependOn(&b.addRunArtifact(tests).step);
}
