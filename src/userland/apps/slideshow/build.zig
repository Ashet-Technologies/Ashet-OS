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
    });
    sdk.installApp(fb_app, .{});
}
