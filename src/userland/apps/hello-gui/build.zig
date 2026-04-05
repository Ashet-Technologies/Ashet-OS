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
        .name = "mtg-counter",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/mtg-counter.zig"),
        .icon = .{
            .convert = b.path("../../../../legacy-stuff/artwork/icons/small-icons/32x32-free-design-icons/32x32/Wizard.png"),
        },
    });
    sdk.installApp(widgets_app, .{});

    const ashetris_app = sdk.addApp(.{
        .name = "ashetris",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/ashetris/ashetris.zig"),
    });
    sdk.installApp(ashetris_app, .{});
}
