const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    const run_step = b.step("run", "Runs the editor with a blank design");

    const args_dep = b.dependency("args", .{});

    const agp_dep = b.dependency("agp", .{});
    const agp_swrast_dep = b.dependency("agp_swrast", .{});
    const ashet_dep = b.dependency("AshetOS", .{ .module_only = true });
    const abi_dep = b.dependency("abi", .{});
    const libgui_dep = b.dependency("libgui", .{});
    const assets_dep = b.dependency("os_assets", .{});

    const zgui_dep = b.dependency("zgui", .{
        .shared = false,
        .with_implot = true,
        .backend = .glfw_opengl3,
        .target = target,
        .optimize = optimize,
    });

    const zglfw_dep = b.dependency("zglfw", .{
        .target = target,
    });

    const zopengl_dep = b.dependency("zopengl", .{
        .target = target,
    });

    const nfd = b.dependency("nfd", .{
        .target = target,
        .optimize = .ReleaseSafe,
    });
    const nfd_mod = nfd.module("nfd");
    const ashet_mod = ashet_dep.module("ashet");

    const standard_widgets_dep = b.dependency("widgets", .{
        .target = .x86,
        .optimize = optimize,
    });
    const standard_widgets_mod = b.createModule(.{
        .root_source_file = standard_widgets_dep.path("src/standard-widgets.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "ashet", .module = ashet_mod },
        },
    });

    const asset_source = assets_dep.namedWriteFiles("assets");
    const mono_8_font = asset_source.getDirectory().path(b, "system/fonts/mono-8.font");
    const sans_6_font = asset_source.getDirectory().path(b, "system/fonts/sans-6.font");

    const editor_mod = b.addModule("gui-editor", .{
        .root_source_file = b.path("src/gui-editor.zig"),

        .target = target,
        .optimize = optimize,

        .imports = &.{
            .{ .name = "standard-widgets", .module = standard_widgets_mod },
            .{ .name = "zgui", .module = zgui_dep.module("root") },
            .{ .name = "zglfw", .module = zglfw_dep.module("root") },
            .{ .name = "zopengl", .module = zopengl_dep.module("root") },
            .{ .name = "ashet", .module = ashet_mod },
            .{ .name = "agp", .module = agp_dep.module("agp") },
            .{ .name = "agp-swrast", .module = agp_swrast_dep.module("agp-swrast") },
            .{ .name = "ashet-abi", .module = abi_dep.module("ashet-abi") },
            .{ .name = "args", .module = args_dep.module("args") },
            .{ .name = "libgui", .module = libgui_dep.module("gui") },
            .{ .name = "mono-8.font", .module = b.createModule(.{ .root_source_file = mono_8_font }) },
            .{ .name = "nfd", .module = nfd_mod },
            .{ .name = "sans-6.font", .module = b.createModule(.{ .root_source_file = sans_6_font }) },
        },
    });

    editor_mod.linkLibrary(zgui_dep.artifact("imgui"));
    editor_mod.linkLibrary(zglfw_dep.artifact("glfw"));

    const editor_exe = b.addExecutable(.{
        .name = "gui-editor",
        .root_module = editor_mod,
    });

    install_system_sdk(b, target, editor_exe.root_module);

    b.installArtifact(editor_exe);

    const compiler_mod = b.addModule("gui-compiler", .{
        .root_source_file = b.path("src/gui-compiler.zig"),
        .target = target,
        .optimize = optimize,
    });

    compiler_mod.addImport("ashet-abi", abi_dep.module("ashet-abi"));
    compiler_mod.addImport("args", args_dep.module("args"));
    compiler_mod.addImport("libgui", libgui_dep.module("gui"));

    const compiler_exe = b.addExecutable(.{
        .name = "gui-compiler",
        .root_module = compiler_mod,
    });
    b.installArtifact(compiler_exe);

    const run_editor = b.addRunArtifact(editor_exe);

    run_editor.addFileArg(b.path("current.gui.json"));

    run_step.dependOn(&run_editor.step);
}

fn install_system_sdk(b: *std.Build, target: std.Build.ResolvedTarget, module: *std.Build.Module) void {
    const system_sdk = b.dependency("system_sdk", .{});

    switch (target.result.os.tag) {
        .windows => {
            if (target.result.cpu.arch.isX86()) {
                if (target.result.abi.isGnu() or target.result.abi.isMusl()) {
                    module.addLibraryPath(system_sdk.path("windows/lib/x86_64-windows-gnu"));
                }
            }
        },
        .macos => {
            module.addLibraryPath(system_sdk.path("macos12/usr/lib"));
            module.addFrameworkPath(system_sdk.path("macos12/System/Library/Frameworks"));
        },
        .linux => {
            if (target.result.cpu.arch.isX86()) {
                module.addLibraryPath(system_sdk.path("linux/lib/x86_64-linux-gnu"));
            } else if (target.result.cpu.arch == .aarch64) {
                module.addLibraryPath(system_sdk.path("linux/lib/aarch64-linux-gnu"));
            }
        },
        else => {},
    }
}
