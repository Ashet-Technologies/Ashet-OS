const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mkfont = b.addExecutable(.{
        .name = "mkfont",
        .root_source_file = b.path("make-bitmap-font.zig"),
        .target = target,
        .optimize = optimize,
    });

    const raw_font_mod = b.createModule(.{
        .root_source_file = b.path("../../kernel/data/font.raw"),
    });
    mkfont.root_module.addImport("raw_font", raw_font_mod);

    b.installArtifact(mkfont);
}
