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

    const bin2c = b.addExecutable(.{
        .name = "bin2c",
        .root_source_file = b.path("util/bin2c.zig"),
        .target = b.graph.host,
    });
    const checksize = b.addExecutable(.{
        .name = "checksize",
        .root_source_file = b.path("util/checksize.zig"),
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
    });
    syslinux.linkLibC();

    syslinux.addIncludePath(b.path("vendor/syslinux-6.03/mtools"));
    syslinux.addIncludePath(b.path("vendor/syslinux-6.03/libinstaller"));
    syslinux.addIncludePath(b.path("vendor/syslinux-6.03/libfat"));
    syslinux.addIncludePath(b.path("vendor/syslinux-6.03/bios/"));

    if (target.result.os.tag == .windows) {
        syslinux.addCSourceFiles(.{
            .root = b.path("vendor"),
            .files = &windows_sources,
            .flags = &flags,
        });
        syslinux.addIncludePath(b.path("vendor/syslinux-6.03/win"));

        const run_checksize = b.addRunArtifact(checksize);
        run_checksize.addFileArg(b.path("vendor/syslinux-6.03/bios/mbr/mbr.bin"));
        const mbr_bin = run_checksize.addOutputFileArg("mbr.bin");
        run_checksize.addArg("440");

        const syslinux_mbr_bin = converToC(bin2c, "syslinux_mbr", mbr_bin);
        syslinux.addCSourceFile(.{ .file = syslinux_mbr_bin, .flags = &flags });
    } else {
        syslinux.addCSourceFiles(.{
            .root = b.path("vendor"),
            .files = &linux_sources,
            .flags = &flags,
        });
    }
    syslinux.addCSourceFile(.{ .file = bootsect_bin, .flags = &flags });
    syslinux.addCSourceFile(.{ .file = ldlinux_bin, .flags = &flags });
    syslinux.addCSourceFile(.{ .file = ldlinuxc32_bin, .flags = &flags });

    b.installArtifact(syslinux);
}

const flags = [_][]const u8{
    "-D_FILE_OFFSET_BITS=64",
    "-fno-sanitize=undefined",
};

const windows_sources = [_][]const u8{
    "syslinux-6.03/win/syslinux.c",
    "syslinux-6.03/win/ntfssect.c",
    "syslinux-6.03/libinstaller/fs.c",
    "syslinux-6.03/libinstaller/syslxmod.c",
    "syslinux-6.03/libinstaller/syslxopt.c",
    "syslinux-6.03/libinstaller/setadv.c",
    "syslinux-6.03/libfat/cache.c",
    "syslinux-6.03/libfat/fatchain.c",
    "syslinux-6.03/libfat/open.c",
    "syslinux-6.03/libfat/searchdir.c",
};

const linux_sources = [_][]const u8{
    "syslinux-6.03/mtools/syslinux.c",
    "syslinux-6.03/libinstaller/fs.c",
    "syslinux-6.03/libinstaller/syslxmod.c",
    "syslinux-6.03/libinstaller/syslxopt.c",
    "syslinux-6.03/libinstaller/setadv.c",
    "syslinux-6.03/libfat/cache.c",
    "syslinux-6.03/libfat/fatchain.c",
    "syslinux-6.03/libfat/open.c",
    "syslinux-6.03/libfat/searchdir.c",
};
