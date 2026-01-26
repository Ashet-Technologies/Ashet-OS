const std = @import("std");

const host_flags: []const []const u8 = &.{
    "-Wall",
    "-g",
    "-MMD",
    "-D_GNU_SOURCE",
    "-fno-math-errno",
    "-fno-trapping-math",
    "-fno-sanitize=undefined", // TODO: Fix this upstream!
};

const c_flags: []const []const u8 = &.{
    "-Wall",
    "-g",
    "-MMD",
    "-D_GNU_SOURCE",
    "-fno-math-errno",
    "-fno-trapping-math",
    "-fno-sanitize=undefined", // TODO: Fix this upstream!
    // "USE_SOFTFLOAT" may be required on some targets?
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const upstream = b.dependency("upstream", .{});

    const stdlib_mod = b.createModule(.{
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
        .link_libc = true,
    });
    stdlib_mod.addCSourceFiles(.{
        .files = &.{
            "mqjs_stdlib.c",
            "mquickjs_build.c",
        },
        .flags = host_flags,
        .root = upstream.path("."),
    });

    const stdlib_exe = b.addExecutable(.{
        .name = "mqjs_stdlib",
        .root_module = stdlib_mod,
    });
    b.installArtifact(stdlib_exe);

    const mqjs_build_flags: []const []const u8 = switch (target.result.ptrBitWidth()) {
        16 => @panic("16 bit builds not supported."),
        32 => comptime &.{"-m32"},
        64 => comptime &.{},
        else => unreachable,
    };
    const gen_atom_h_run = b.addRunArtifact(stdlib_exe);
    gen_atom_h_run.addArg("-a");
    gen_atom_h_run.addArgs(mqjs_build_flags);
    const mquickjs_atom_h_path = gen_atom_h_run.captureStdOut();

    const gen_stdlib_h_run = b.addRunArtifact(stdlib_exe);
    gen_stdlib_h_run.addArgs(mqjs_build_flags);
    const mquickjs_stdlib_h_path = gen_stdlib_h_run.captureStdOut();

    const include_dir = b.addWriteFiles();
    _ = include_dir.addCopyFile(mquickjs_atom_h_path, "mquickjs_atom.h");
    _ = include_dir.addCopyFile(mquickjs_stdlib_h_path, "mqjs_stdlib.h");

    const mqjs_mod = b.addModule("mqjs", .{
        .root_source_file = null,
        .target = target,
        .optimize = optimize,
        .link_libc = false,
    });
    mqjs_mod.addIncludePath(upstream.path("."));
    mqjs_mod.addIncludePath(include_dir.getDirectory());
    mqjs_mod.addCSourceFiles(.{
        .files = &.{
            "mquickjs.c",
            "dtoa.c",
            "libm.c",
            "cutils.c",
        },
        .flags = c_flags,
        .root = upstream.path("."),
    });

    const mqjs_cli_mod = b.createModule(.{
        .root_source_file = null,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "mqjs", .module = mqjs_mod },
        },
    });

    mqjs_cli_mod.addCSourceFiles(.{
        .files = &.{
            "mqjs.c",
            "readline_tty.c",
            "readline.c",
        },
        .flags = c_flags,
        .root = upstream.path("."),
    });

    const mqjs_exe = b.addExecutable(.{
        .name = "mqjs",
        .root_module = mqjs_cli_mod,
    });

    b.installArtifact(mqjs_exe);
}
