const std = @import("std");

pub fn build(b: *std.Build) void {

    // Dependencies:
    const abi_dep = b.dependency("abi", .{});
    const std_dep = b.dependency("std", .{});
    const agp_dep = b.dependency("agp", .{});
    const libgui_dep = b.dependency("libgui", .{});

    // Modules:

    const std_mod = std_dep.module("ashet-std");
    const agp_mod = agp_dep.module("agp");

    const abi_mod = abi_dep.module("ashet-abi");
    const widget_def_model_mod = libgui_dep.module("widgets-model");

    const widgets_json = libgui_dep.namedLazyPath("standard-widgets.json");

    const gen_widget_types_exe = b.addExecutable(.{
        .name = "gen-widget-types",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .root_source_file = b.path("tools/gen-widget-types.zig"),
            .imports = &.{
                .{ .name = "widget-def-model", .module = widget_def_model_mod },
            },
        }),
    });
    b.installArtifact(gen_widget_types_exe);

    const gen_widgets_defs = b.addRunArtifact(gen_widget_types_exe);
    gen_widgets_defs.addFileArg(widgets_json);
    const widgets_mod_src = gen_widgets_defs.addOutputFileArg("widgets.zig");

    b.getInstallStep().dependOn(&b.addInstallFile(widgets_mod_src, "widgets.zig").step);

    const ashet_module = b.addModule("ashet", .{
        .root_source_file = b.path("src/libashet.zig"),
        .imports = &.{
            .{ .name = "agp", .module = agp_mod },
            .{ .name = "ashet-std", .module = std_mod },
            .{ .name = "ashet-abi", .module = abi_mod },
        },
    });

    const widgets_mod = b.createModule(.{
        .root_source_file = widgets_mod_src,
        .imports = &.{
            .{ .name = "ashet", .module = ashet_module },
        },
    });
    ashet_module.addImport("widgets", widgets_mod);
}
