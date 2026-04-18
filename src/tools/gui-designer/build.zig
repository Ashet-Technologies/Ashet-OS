const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    const run_step = b.step("run", "Runs the editor with a blank design");

    const args_dep = b.dependency("args", .{});

    const abi_dep = b.dependency("abi", .{});
    const libgui_dep = b.dependency("libgui", .{});

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

    const editor_mod = b.addModule("gui-editor", .{
        .root_source_file = b.path("src/gui-editor.zig"),

        .target = target,
        .optimize = optimize,
    });

    editor_mod.addImport("zgui", zgui_dep.module("root"));
    editor_mod.linkLibrary(zgui_dep.artifact("imgui"));

    editor_mod.addImport("zglfw", zglfw_dep.module("root"));
    editor_mod.linkLibrary(zglfw_dep.artifact("glfw"));

    editor_mod.addImport("zopengl", zopengl_dep.module("root"));
    editor_mod.addImport("ashet-abi", abi_dep.module("ashet-abi"));
    editor_mod.addImport("args", args_dep.module("args"));
    editor_mod.addImport("libgui", libgui_dep.module("gui"));

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
