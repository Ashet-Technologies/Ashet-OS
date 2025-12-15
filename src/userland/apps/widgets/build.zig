const std = @import("std");
const AshetOS = @import("AshetOS");

pub fn build(b: *std.Build) void {
    const target = AshetOS.standardTargetOption(b);
    const optimize = b.standardOptimizeOption(.{});

    const agp_dep = b.dependency("agp", .{});
    const abi_dep = b.dependency("abi", .{});

    const agp_mod = agp_dep.module("agp");
    const abi_mod = abi_dep.module("ashet-abi");

    const draw_mod = b.addModule("draw", .{
        .root_source_file = b.path("src/draw.zig"),
        .optimize = optimize,
        .imports = &.{
            .{ .name = "agp", .module = agp_mod },
            .{ .name = "abi", .module = abi_mod },
        },
    });

    _ = draw_mod;

    const sdk = AshetOS.init(b, "AshetOS", .{ .target = target });

    const app = sdk.addApp(.{
        .name = "standard",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/standard-widgets.zig"),
    });

    sdk.installApp(app, .{});
}
