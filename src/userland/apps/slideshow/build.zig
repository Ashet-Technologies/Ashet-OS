const std = @import("std");
const AshetOS = @import("AshetOS");

pub fn build(b: *std.Build) void {
    const target = AshetOS.standardTargetOption(b);
    const optimize = b.standardOptimizeOption(.{});

    const sdk = AshetOS.init(b, "AshetOS", .{ .target = target });

    const fb_app = sdk.addApp(.{
        .name = "slideshow",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/slideshow.zig"),
        .icon = .{
            .convert = b.path("../../../../legacy-stuff/artwork/icons/small-icons/32x32-free-design-icons/32x32/Synchronize.png"),
        },
    });
    sdk.installApp(fb_app, .{});
}
