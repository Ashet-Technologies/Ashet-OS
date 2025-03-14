const std = @import("std");

pub fn build(b: *std.Build) void {
    const ashet_dep = b.dependency("AshetOS", .{ .module_only = true });
    const texteditor_dep = b.dependency("text-editor", .{});

    const ashet_mod = ashet_dep.module("ashet");
    const texteditor_mod = texteditor_dep.module("text-editor");

    const gui_mod = b.addModule("ashet-gui", .{
        .root_source_file = b.path("gui.zig"),
        .imports = &.{
            .{ .name = "ashet", .module = ashet_mod },
            .{ .name = "text-editor", .module = texteditor_mod },
        },
    });
    _ = gui_mod;
}
