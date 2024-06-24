const std = @import("std");

const mkicon = @import("mkicon");

pub fn build(b: *std.Build) void {
    const mkicon_dep = b.dependency("mkicon", .{});

    const converter = mkicon.Converter.create(b, mkicon_dep);

    _ = converter;

    // const system_icons = createSystemIcons(b, converter, &rootfs);

    // const system_assets = b.addModule("assets", .{
    //     .root_source_file = system_icons.getOutput(),
    // });
}

// fn createSystemIcons(b: *std.Build, bmpconv: mkicon.Converter, rootfs: ?*disk_image_step.FileSystemBuilder) *AssetBundleStep {
//     const system_icons = AssetBundleStep.create(b, rootfs);

//     {
//         const desktop_icon_conv_options: BitmapConverter.Options = .{
//             .geometry = .{ 32, 32 },
//             .palette = .{
//                 .predefined = b.path("src/kernel/data/palette.gpl"),
//             },
//         };

//         const tool_icon_conv_options: BitmapConverter.Options = .{
//             .geometry = .{ 16, 16 },
//             .palette = .{
//                 .predefined = b.path("src/kernel/data/palette.gpl"),
//             },
//         };
//         system_icons.add("system/icons/back.abm", bmpconv.convert(b.path("artwork/icons/small-icons/16x16-free-application-icons/16x16/Go back.png"), "back.abm", tool_icon_conv_options));
//         system_icons.add("system/icons/forward.abm", bmpconv.convert(b.path("artwork/icons/small-icons/16x16-free-application-icons/16x16/Go forward.png"), "forward.abm", tool_icon_conv_options));
//         system_icons.add("system/icons/reload.abm", bmpconv.convert(b.path("artwork/icons/small-icons/16x16-free-application-icons/16x16/Refresh.png"), "reload.abm", tool_icon_conv_options));
//         system_icons.add("system/icons/home.abm", bmpconv.convert(b.path("artwork/icons/small-icons/16x16-free-application-icons/16x16/Home.png"), "home.abm", tool_icon_conv_options));
//         system_icons.add("system/icons/go.abm", bmpconv.convert(b.path("artwork/icons/small-icons/16x16-free-application-icons/16x16/Go.png"), "go.abm", tool_icon_conv_options));
//         system_icons.add("system/icons/stop.abm", bmpconv.convert(b.path("artwork/icons/small-icons/16x16-free-application-icons/16x16/Stop sign.png"), "stop.abm", tool_icon_conv_options));
//         system_icons.add("system/icons/menu.abm", bmpconv.convert(b.path("artwork/icons/small-icons/16x16-free-application-icons/16x16/Tune.png"), "menu.abm", tool_icon_conv_options));
//         system_icons.add("system/icons/plus.abm", bmpconv.convert(b.path("artwork/icons/small-icons/16x16-free-toolbar-icons/13.png"), "plus.abm", tool_icon_conv_options));
//         system_icons.add("system/icons/delete.abm", bmpconv.convert(b.path("artwork/icons/small-icons/16x16-free-application-icons/16x16/Delete.png"), "delete.abm", tool_icon_conv_options));
//         system_icons.add("system/icons/copy.abm", bmpconv.convert(b.path("artwork/icons/small-icons/16x16-free-application-icons/16x16/Copy.png"), "copy.abm", tool_icon_conv_options));
//         system_icons.add("system/icons/cut.abm", bmpconv.convert(b.path("artwork/icons/small-icons/16x16-free-application-icons/16x16/Cut.png"), "cut.abm", tool_icon_conv_options));
//         system_icons.add("system/icons/paste.abm", bmpconv.convert(b.path("artwork/icons/small-icons/16x16-free-application-icons/16x16/Paste.png"), "paste.abm", tool_icon_conv_options));

//         system_icons.add("system/icons/default-app-icon.abm", bmpconv.convert(b.path("artwork/os/default-app-icon.png"), "menu.abm", desktop_icon_conv_options));
//     }

//     return system_icons;
// }
