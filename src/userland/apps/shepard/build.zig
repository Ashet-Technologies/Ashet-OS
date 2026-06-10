const std = @import("std");
const AshetOS = @import("AshetOS");

pub fn build(b: *std.Build) void {
    const target = AshetOS.standardTargetOption(b);
    const optimize = b.standardOptimizeOption(.{});

    const sdk = AshetOS.init(b, "AshetOS", .{ .target = target });

    const shepard_app = sdk.addApp(.{
        .name = "shepard",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/commander.zig"),
        .icon = .{
            .convert = b.path("../../../../assets/icons/apps/commander.png"),
        },
    });
    sdk.installApp(shepard_app, .{});
}
