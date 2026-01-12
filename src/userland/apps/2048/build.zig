const std = @import("std");
const AshetOS = @import("AshetOS");

pub fn build(b: *std.Build) void {
    const target = AshetOS.standardTargetOption(b);
    const optimize = b.standardOptimizeOption(.{});

    const sdk = AshetOS.init(b, "AshetOS", .{ .target = target });

    const app = sdk.addApp(.{
        .name = "2048",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("2048.zig"),
        .icon = .{
            .convert = b.path("../../../../assets/icons/apps/2048.png"),
        },
    });

    sdk.installApp(app, .{});
}
