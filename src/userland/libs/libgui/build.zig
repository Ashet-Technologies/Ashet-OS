const std = @import("std");

pub fn build(b: *std.Build) void {
    const ashet_dep = b.dependency("AshetOS", .{ .module_only = true });
    const ashet_mod = ashet_dep.module("ashet");

    _ = b.addModule("gui", .{
        .root_source_file = b.path("src/libgui.zig"),
        .imports = &.{
            .{ .name = "ashet", .module = ashet_mod },
            // .{ .name = "text-editor", .module = texteditor_mod },
        },
    });
}
