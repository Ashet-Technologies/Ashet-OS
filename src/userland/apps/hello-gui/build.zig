const std = @import("std");
const AshetOS = @import("AshetOS");

pub fn build(b: *std.Build) void {
    const target = AshetOS.standardTargetOption(b);
    const optimize = b.standardOptimizeOption(.{});

    const sdk = AshetOS.init(b, "AshetOS", .{ .target = target });

    const fb_app = sdk.addApp(.{
        .name = "hello-fb",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/hello-framebuffer.zig"),
    });
    sdk.installApp(fb_app, .{});

    const widgets_app = sdk.addApp(.{
        .name = "hello-widgets",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/hello-widgets.zig"),
    });
    sdk.installApp(widgets_app, .{});
}
