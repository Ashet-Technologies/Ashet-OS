const std = @import("std");

const mkicon = @import("mkicon");

pub fn build(b: *std.Build) void {
    const mkicon_dep = b.dependency("mkicon", .{});

    const converter = mkicon.Converter.create(b, mkicon_dep);

    const desktop_icon_conv_options: mkicon.ConvertOptions = .{
        .geometry = .{ 32, 32 },
        .palette = .{
            .predefined = b.path("../kernel/data/palette.gpl"),
        },
    };

    const tool_icon_conv_options: mkicon.ConvertOptions = .{
        .geometry = .{ 16, 16 },
        .palette = .{
            .predefined = b.path("../kernel/data/palette.gpl"),
        },
    };

    const rootfs = RootFS{ .write_file = b.addNamedWriteFiles("assets") };

    rootfs.install(
        "system/icons/back.abm",
        converter.convert(b.path("../../artwork/icons/small-icons/16x16-free-application-icons/16x16/Go back.png"), "back.abm", tool_icon_conv_options),
    );
    rootfs.install(
        "system/icons/forward.abm",
        converter.convert(b.path("../../artwork/icons/small-icons/16x16-free-application-icons/16x16/Go forward.png"), "forward.abm", tool_icon_conv_options),
    );
    rootfs.install(
        "system/icons/reload.abm",
        converter.convert(b.path("../../artwork/icons/small-icons/16x16-free-application-icons/16x16/Refresh.png"), "reload.abm", tool_icon_conv_options),
    );
    rootfs.install(
        "system/icons/home.abm",
        converter.convert(b.path("../../artwork/icons/small-icons/16x16-free-application-icons/16x16/Home.png"), "home.abm", tool_icon_conv_options),
    );
    rootfs.install(
        "system/icons/go.abm",
        converter.convert(b.path("../../artwork/icons/small-icons/16x16-free-application-icons/16x16/Go.png"), "go.abm", tool_icon_conv_options),
    );
    rootfs.install(
        "system/icons/stop.abm",
        converter.convert(b.path("../../artwork/icons/small-icons/16x16-free-application-icons/16x16/Stop sign.png"), "stop.abm", tool_icon_conv_options),
    );
    rootfs.install(
        "system/icons/menu.abm",
        converter.convert(b.path("../../artwork/icons/small-icons/16x16-free-application-icons/16x16/Tune.png"), "menu.abm", tool_icon_conv_options),
    );
    rootfs.install(
        "system/icons/plus.abm",
        converter.convert(b.path("../../artwork/icons/small-icons/16x16-free-toolbar-icons/13.png"), "plus.abm", tool_icon_conv_options),
    );
    rootfs.install(
        "system/icons/delete.abm",
        converter.convert(b.path("../../artwork/icons/small-icons/16x16-free-application-icons/16x16/Delete.png"), "delete.abm", tool_icon_conv_options),
    );
    rootfs.install(
        "system/icons/copy.abm",
        converter.convert(b.path("../../artwork/icons/small-icons/16x16-free-application-icons/16x16/Copy.png"), "copy.abm", tool_icon_conv_options),
    );
    rootfs.install(
        "system/icons/cut.abm",
        converter.convert(b.path("../../artwork/icons/small-icons/16x16-free-application-icons/16x16/Cut.png"), "cut.abm", tool_icon_conv_options),
    );
    rootfs.install(
        "system/icons/paste.abm",
        converter.convert(b.path("../../artwork/icons/small-icons/16x16-free-application-icons/16x16/Paste.png"), "paste.abm", tool_icon_conv_options),
    );

    rootfs.install(
        "system/icons/default-app-icon.abm",
        converter.convert(b.path("../../artwork/os/default-app-icon.png"), "menu.abm", desktop_icon_conv_options),
    );

    rootfs.install(
        "apps/clock/icon",
        converter.convert(b.path("../../artwork/icons/small-icons/32x32-free-design-icons/32x32/Time.png"), "clock.abm", desktop_icon_conv_options),
    );
}

const RootFS = struct {
    write_file: *std.Build.Step.WriteFile,

    pub fn install(rootfs: RootFS, path: []const u8, source: std.Build.LazyPath) void {
        _ = rootfs.write_file.addCopyFile(source, path);
    }
};
