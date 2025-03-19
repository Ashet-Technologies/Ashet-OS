const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const args_mod = b.dependency("args", .{}).module("args");
    const abi_mod = b.dependency("abi", .{}).module("ashet-abi");

    const zigimg_mod = b.dependency("zigimg", .{}).module("zigimg");

    const mkfont_mod = b.addModule("mkfont", .{
        .root_source_file = b.path("make-font.zig"),
        .target = target,
        .optimize = optimize,
    });

    mkfont_mod.addImport("zigimg", zigimg_mod);
    mkfont_mod.addImport("ashet-abi", abi_mod);
    mkfont_mod.addImport("args", args_mod);

    const mkfont_exe = b.addExecutable(.{
        .name = "mkfont",
        .root_module = mkfont_mod,
    });

    b.installArtifact(mkfont_exe);
}
