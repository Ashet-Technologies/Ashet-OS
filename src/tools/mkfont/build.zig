const std = @import("std");

pub fn build(b: *std.Build) !void {
    const run_step = b.step("run", "Run the app");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    const stb_dep = b.dependency("stb", .{});

    const args_mod = b.dependency("args", .{}).module("args");
    const abi_mod = b.dependency("abi", .{}).module("ashet-abi");

    const zigimg_mod = b.dependency("zigimg", .{}).module("zigimg");
    const turtlefont_mod = b.dependency("turtlefont", .{}).module("turtlefont");

    const mkfont_mod = b.addModule("mkfont", .{
        .root_source_file = b.path("src/make-font.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    mkfont_mod.addIncludePath(stb_dep.path("."));
    mkfont_mod.addCSourceFile(.{
        .file = b.path("src/stb_truetype.c"),
        .flags = &.{},
        .language = .c,
    });

    mkfont_mod.addImport("zigimg", zigimg_mod);
    mkfont_mod.addImport("turtlefont", turtlefont_mod);
    mkfont_mod.addImport("ashet-abi", abi_mod);
    mkfont_mod.addImport("args", args_mod);

    const mkfont_exe = b.addExecutable(.{
        .name = "mkfont",
        .root_module = mkfont_mod,
    });

    b.installArtifact(mkfont_exe);

    const run_cmd = b.addRunArtifact(mkfont_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    run_step.dependOn(&run_cmd.step);
}
