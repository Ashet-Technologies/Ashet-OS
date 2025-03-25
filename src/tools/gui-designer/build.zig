const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    const run_step = b.step("run", "Runs the editor with a blank design");

    const args_dep = b.dependency("args", .{});

    const abi_dep = b.dependency("abi", .{});

    const zgui_dep = b.dependency("zgui", .{
        .shared = false,
        .with_implot = true,
        .backend = .glfw_opengl3,
    });

    const zglfw_dep = b.dependency("zglfw", .{
        .target = target,
    });

    const zopengl_dep = b.dependency("zopengl", .{});

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

    const editor_exe = b.addExecutable(.{
        .name = "gui-editor",
        .root_module = editor_mod,
    });

    if (target.result.os.tag == .linux) {
        if (b.lazyDependency("system_sdk", .{})) |system_sdk| {
            editor_exe.addLibraryPath(system_sdk.path("linux/lib/x86_64-linux-gnu"));
        }
    }

    b.installArtifact(editor_exe);

    const run_editor = b.addRunArtifact(editor_exe);

    run_editor.addFileArg(b.path("current.gui.json"));

    run_step.dependOn(&run_editor.step);
}
