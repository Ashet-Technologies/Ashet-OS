const std = @import("std");
const AshetOS = @import("AshetOS");

pub fn build(b: *std.Build) void {
    const target = AshetOS.standardTargetOption(b);
    const optimize = b.standardOptimizeOption(.{});

    const agp_dep = b.dependency("agp", .{});
    const abi_dep = b.dependency("abi", .{});
    const libgui_dep = b.dependency("libgui", .{});
    const codegen_dep = b.dependency("widgets_codegen", .{});

    const agp_mod = agp_dep.module("agp");
    const abi_mod = abi_dep.module("ashet-abi");

    const draw_mod = b.addModule("draw", .{
        .root_source_file = b.path("src/draw.zig"),
        .optimize = optimize,
        .imports = &.{
            .{ .name = "agp", .module = agp_mod },
            .{ .name = "abi", .module = abi_mod },
        },
    });

    _ = draw_mod;

    const sdk = AshetOS.init(b, "AshetOS", .{ .target = target });

    const widgets_codegen_exe = codegen_dep.artifact("widgets-codegen");
    const generate_widgets_module = b.addRunArtifact(widgets_codegen_exe);
    generate_widgets_module.addFileArg(libgui_dep.namedLazyPath("standard-widgets.json"));
    const generated_widgets_zig = generate_widgets_module.addPrefixedOutputFileArg(
        "--output=",
        "widgets-generated.zig",
    );

    const install_generated_widgets = b.addInstallFile(generated_widgets_zig, "widgets-generated.zig");
    b.getInstallStep().dependOn(&install_generated_widgets.step);

    const app = sdk.addApp(.{
        .name = "widgets",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/standard-widgets.zig"),
    });

    const widgets_module = b.createModule(.{
        .root_source_file = generated_widgets_zig,
        .imports = &.{
            .{ .name = "standard-widgets", .module = app.exe.root_module },
            .{ .name = "ashet", .module = sdk.ashet_module },
        },
    });

    app.exe.step.dependOn(&install_generated_widgets.step);
    app.exe.root_module.addImport("generated_widgets", widgets_module);

    sdk.installApp(app, .{});
}
