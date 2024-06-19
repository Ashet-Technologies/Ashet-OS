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
    lua: *std.Build.Step.Compile,
    mod_ashet_gui: *std.Build.Module,
    mod_ashet: *std.Build.Module,
    mod_system_assets: *std.Build.Module,

    pub fn render(gen: UiGenerator, input: std.Build.LazyPath) *std.Build.Module {
        const runner = gen.builder.addRunArtifact(gen.lua);
        runner.cwd = gen.builder.path(".");
        runner.addFileArg(gen.builder.path("tools/ui-layouter.lua"));
        runner.addFileArg(input);
        const out_file = runner.addOutputFileArg("ui-layout.zig");

        return gen.builder.createModule(.{
            .root_source_file = out_file,
            .imports = &.{
                .{ .name = "ashet", .module = gen.mod_ashet },
                .{ .name = "ashet-gui", .module = gen.mod_ashet_gui },
                .{ .name = "system-assets", .module = gen.mod_system_assets },
            },
        });
    }
};
