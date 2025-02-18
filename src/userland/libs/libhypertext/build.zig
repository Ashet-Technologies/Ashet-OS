const std = @import("std");

pub fn build(b: *std.Build) void {
    const ashet_dep = b.dependency("AshetOS", .{ .module_only = true });
    const hyperdoc_dep = b.dependency("hyperdoc", .{});

    const ashet_mod = ashet_dep.module("ashet");
    const hyperdoc_mod = hyperdoc_dep.module("hyperdoc");

    const hypertext_mod = b.addModule("hypertext", .{
        .root_source_file = b.path("hypertext.zig"),
        .imports = &.{
            .{ .name = "ashet", .module = ashet_mod },
            .{ .name = "hyperdoc", .module = hyperdoc_mod },
        },
    });
    _ = hypertext_mod;
}
