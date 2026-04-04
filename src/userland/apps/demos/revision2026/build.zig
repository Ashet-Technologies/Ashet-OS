const std = @import("std");
const AshetOS = @import("AshetOS");

pub fn build(b: *std.Build) void {
    const target = AshetOS.standardTargetOption(b);
    const optimize = b.standardOptimizeOption(.{});

    const sdk = AshetOS.init(b, "AshetOS", .{ .target = target });

    const app = sdk.addApp(.{
        .name = "revision2026",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("revision2026.zig"),
    });

    sdk.install_file("/etc/revision/bricks.abm", sdk.convert_image(b.path("data/Brick01.png"), .{
        .geometry = .{ 64, 64 },
    }));
    sdk.install_file("/etc/revision/metal.abm", sdk.convert_image(b.path("data/Doors10.png"), .{
        .geometry = .{ 64, 64 },
    }));
    sdk.install_file("/etc/revision/stones.abm", sdk.convert_image(b.path("data/Stone01.png"), .{
        .geometry = .{ 64, 64 },
    }));
    sdk.install_file("/etc/revision/tiles.abm", sdk.convert_image(b.path("data/Tiles05.png"), .{
        .geometry = .{ 64, 64 },
    }));

    sdk.installApp(app, .{});
}
