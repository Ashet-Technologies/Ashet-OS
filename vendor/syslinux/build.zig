const std = @import("std");

fn converToC(bin2c: *std.Build.Step.Compile, symbol_name: []const u8, path: std.Build.LazyPath) std.Build.LazyPath {
    const runner = bin2c.step.owner.addRunArtifact(bin2c);
    runner.addArg(symbol_name);
    runner.addFileArg(path);
    return runner.addOutputFileArg("output.c");
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    const zfat_dep = b.dependency("zfat", .{
        .code_page = .us,
        .@"volume-count" = @as(u32, 1),
        .@"sector-size" = @as(u32, 512),
        .chmod = true,
    });
    const zfat_mod = zfat_dep.module("zfat");

    const bin2c = b.addExecutable(.{
        .name = "bin2c",
        .root_source_file = b.path("util/bin2c.zig"),
        .target = b.graph.host,
    });
    // b.installArtifact(bin2c);

    const bootsect_bin = converToC(bin2c, "syslinux_bootsect", b.path("vendor/syslinux-6.03/bios/core/ldlinux.bss"));
    const ldlinux_bin = converToC(bin2c, "syslinux_ldlinux", b.path("vendor/syslinux-6.03/bios/core/ldlinux.sys"));
    const ldlinuxc32_bin = converToC(bin2c, "syslinux_ldlinuxc32", b.path("vendor/syslinux-6.03/bios/com32/elflink/ldlinux/ldlinux.c32"));

    const syslinux = b.addExecutable(.{
        .name = "syslinux",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("fork/mtools_replacement.zig"),
    });
    syslinux.root_module.addImport("zfat", zfat_mod);
    syslinux.linkLibC();

    syslinux.addIncludePath(b.path("fork"));
    syslinux.addIncludePath(b.path("vendor/syslinux-6.03/mtools"));
    syslinux.addIncludePath(b.path("vendor/syslinux-6.03/libinstaller"));
    syslinux.addIncludePath(b.path("vendor/syslinux-6.03/libfat"));
    syslinux.addIncludePath(b.path("vendor/syslinux-6.03/bios/"));

    syslinux.addCSourceFile(.{
        .file = b.path("fork/syslinux.c"),
        .flags = &.{
            "-D_FILE_OFFSET_BITS=64",
            "-Wall",
            "-Wextra",
        },
    });

    syslinux.addCSourceFiles(.{
        .root = b.path("vendor"),
        .files = &sources,
        .flags = &flags,
    });
    syslinux.addCSourceFile(.{ .file = bootsect_bin, .flags = &flags });
    syslinux.addCSourceFile(.{ .file = ldlinux_bin, .flags = &flags });
    syslinux.addCSourceFile(.{ .file = ldlinuxc32_bin, .flags = &flags });

    b.installArtifact(syslinux);
}

const flags = [_][]const u8{
    "-D_FILE_OFFSET_BITS=64",
    "-fno-sanitize=undefined",
};

const sources = [_][]const u8{
    // "syslinux-6.03/mtools/syslinux.c", // we forked that file to work with our own code
    "syslinux-6.03/libinstaller/fs.c",
    "syslinux-6.03/libinstaller/syslxmod.c",
    "syslinux-6.03/libinstaller/syslxopt.c",
    "syslinux-6.03/libinstaller/setadv.c",
    "syslinux-6.03/libfat/cache.c",
    "syslinux-6.03/libfat/fatchain.c",
    "syslinux-6.03/libfat/open.c",
    "syslinux-6.03/libfat/searchdir.c",
};
