const std = @import("std");

pub fn build(b: *std.Build) void {
    const abi_dep = b.dependency("abi", .{});

    const abi_mod = abi_dep.module("ashet-abi");

    const mod = b.addModule("agp", .{
        .root_source_file = b.path("src/agp.zig"),
    });

    mod.addImport("ashet-abi", abi_mod);
}
