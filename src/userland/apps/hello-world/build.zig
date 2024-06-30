const std = @import("std");
const AshetOS = @import("AshetOS");

pub fn build(b: *std.Build) void {
    const target = AshetOS.standardTargetOption(b);
    const optimize = b.standardOptimizeOption(.{});

    const ashet_dep = b.dependency("AshetOS", .{ .target = target });

    const ashet_lib = ashet_dep.artifact("AshetOS");
    const ashet_mod = ashet_dep.module("ashet");

    const exe = AshetOS.addExecutable(b, .{
        .name = "hello-world",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("hello-world.zig"),
    });

    // Not mandatory, but really really sensible:
    exe.linkLibrary(ashet_lib);
    exe.root_module.addImport("ashet", ashet_mod);

    // Same for all applications:
    exe.setLinkerScript(ashet_dep.path("application.ld"));

    b.installArtifact(exe);

    // const install = ctx.b.addInstallFileWithDir(
    //     exe.getEmittedBin(),
    //     .{ .custom = ctx.b.fmt("apps/{s}", .{@tagName(info.platform)}) }, // apps are the same *per platform*, not *per target*!
    //     exe.name,
    // );
    // ctx.b.getInstallStep().dependOn(&install.step);

    // info.rootfs.addFile(exe.getEmittedBin(), ctx.b.fmt("apps/{s}/code", .{name}));

    // const icon_file = if (maybe_icon) |src_icon| blk: {
    //     const icon_file = ctx.bmpconv.convert(
    //         ctx.b.path(src_icon),
    //         ctx.b.fmt("{s}.icon", .{name}),
    //         .{
    //             .geometry = .{ 32, 32 },
    //             .palette = .{ .predefined = ctx.b.path("src/kernel/data/palette.gpl") },
    //             // .palette = .{ .sized = 15 },
    //         },
    //     );

    //     info.rootfs.addFile(icon_file, ctx.b.fmt("apps/{s}/icon", .{name}));
    //     break :blk icon_file;
    // } else null;

}
