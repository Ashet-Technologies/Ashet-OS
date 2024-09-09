const std = @import("std");

pub fn build(b: *std.Build) void {
    const abi_dep = b.dependency("abi", .{});
    const agp_dep = b.dependency("agp", .{});
    const turtlefont_dep = b.dependency("turtlefont", .{});

    const abi_mod = abi_dep.module("ashet-abi");
    const agp_mod = agp_dep.module("agp");
    const turtlefont_mod = turtlefont_dep.module("turtlefont");

    const mod = b.addModule("agp-swrast", .{
        .root_source_file = b.path("src/agp-swrast.zig"),
    });

    mod.addImport("ashet-abi", abi_mod);
    mod.addImport("agp", agp_mod);
    mod.addImport("turtlefont", turtlefont_mod);
}
