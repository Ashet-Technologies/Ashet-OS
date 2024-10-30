const std = @import("std");
const AshetOS = @import("AshetOS");

pub fn build(b: *std.Build) void {
    const target = AshetOS.standardTargetOption(b);
    const optimize = b.standardOptimizeOption(.{});

    const sdk = AshetOS.init(b, "AshetOS", .{ .target = target });

    const app = sdk.addApp(.{
        .name = "paint",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("paint.zig"),
        .icon = .{
            .convert = b.path("../../../../artwork/icons/small-icons/32x32-free-design-icons/32x32/Painter.png"),
        },
    });

    sdk.installApp(app, .{});
}
