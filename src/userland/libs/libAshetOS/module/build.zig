const std = @import("std");

pub fn build(b: *std.Build) void {

    // Dependencies:
    const abi_dep = b.dependency("abi", .{});
    const std_dep = b.dependency("std", .{});
    const agp_dep = b.dependency("agp", .{});

    // Modules:

    const std_mod = std_dep.module("ashet-std");
    const agp_mod = agp_dep.module("agp");

    const abi_mod = abi_dep.module("ashet-abi");

    _ = b.addModule("ashet", .{
        .root_source_file = b.path("src/libashet.zig"),
        .imports = &.{
            .{ .name = "agp", .module = agp_mod },
            .{ .name = "ashet-std", .module = std_mod },
            .{ .name = "ashet-abi", .module = abi_mod },
        },
    });
}
