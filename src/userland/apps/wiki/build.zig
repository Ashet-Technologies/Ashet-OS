const std = @import("std");
const AshetOS = @import("AshetOS");

pub fn build(b: *std.Build) void {
    const target = AshetOS.standardTargetOption(b);
    const optimize = b.standardOptimizeOption(.{});

    const hyperdoc_dep = b.dependency("hyperdoc", .{});
    const hypertext_dep = b.dependency("hypertext", .{});
    // const gui_dep = b.dependency("ashet-gui", .{});

    const hyperdoc_mod = hyperdoc_dep.module("hyperdoc");
    const hypertext_mod = hypertext_dep.module("hypertext");
    // const gui_mod = gui_dep.module("ashet-gui");

    const sdk = AshetOS.init(b, "AshetOS", .{ .target = target });

    const app = sdk.addApp(.{
        .name = "wiki",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/wiki.zig"),
        .icon = .{
            .convert = b.path("../../../../assets/icons/apps/wiki.png"),
        },
    });

    app.exe.root_module.addImport("hyperdoc", hyperdoc_mod);
    app.exe.root_module.addImport("hypertext", hypertext_mod);
    // app.exe.root_module.addImport("ashet-gui", gui_mod);
    // .{ .name = "ui-layout", .module = undefined },

    sdk.installApp(app, .{});
}
