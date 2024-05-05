const std = @import("std");

pub const Modules = struct {
    hyperdoc: *std.Build.Module,
    args: *std.Build.Module,
    zigimg: *std.Build.Module,
    fraxinus: *std.Build.Module,
    ashet_std: *std.Build.Module,
    virtio: *std.Build.Module,
    ashet_abi: *std.Build.Module,
    libashet: *std.Build.Module,
    ashet_gui: *std.Build.Module,
    libhypertext: *std.Build.Module,
    libashetfs: *std.Build.Module,
    fatfs: *std.Build.Module,
    network: *std.Build.Module,
    vnc: *std.Build.Module,

    // system_assets: *std.Build.Module,
};

pub const UiGenerator = struct {
    builder: *std.Build,
    lua: *std.Build.CompileStep,
    mod_ashet_gui: *std.Build.Module,
    mod_ashet: *std.Build.Module,
    mod_system_assets: *std.Build.Module,

    pub fn render(gen: @This(), input: std.Build.FileSource) *std.Build.Module {
        const runner = gen.builder.addRunArtifact(gen.lua);
        runner.cwd = gen.builder.pathFromRoot(".");
        runner.addFileSourceArg(.{ .path = gen.builder.pathFromRoot("tools/ui-layouter.lua") });
        runner.addFileSourceArg(input);
        const out_file = runner.addOutputFileArg("ui-layout.zig");

        return gen.builder.createModule(.{
            .source_file = out_file,
            .dependencies = &.{
                .{ .name = "ashet", .module = gen.mod_ashet },
                .{ .name = "ashet-gui", .module = gen.mod_ashet_gui },
                .{ .name = "system-assets", .module = gen.mod_system_assets },
            },
        });
    }
};
