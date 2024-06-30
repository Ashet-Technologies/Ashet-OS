const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const extract_icon = b.addExecutable(.{
        .name = "extract-icon",
        .root_source_file = b.path("extract-icon.zig"),
        .target = target,
        .optimize = optimize,
    });

    const args_mod = b.dependency("args", .{}).module("args");
    const zigimg_mod = b.dependency("zigimg", .{}).module("zigimg");
    const ashet_abi_mod = b.dependency("ashet-abi", .{}).module("ashet-abi");

    extract_icon.root_module.addImport("args", args_mod);
    extract_icon.root_module.addImport("zigimg", zigimg_mod);
    extract_icon.root_module.addImport("ashet-abi", ashet_abi_mod);

    b.installArtifact(extract_icon);
}
