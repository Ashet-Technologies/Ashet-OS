const std = @import("std");

const mkicon = @import("mkicon");

pub fn build(b: *std.Build) void {
    const mkicon_dep = b.dependency("mkicon", .{});
    const mkfont_dep = b.dependency("mkfont", .{});

    const mkfont_exe = mkfont_dep.artifact("mkfont");

    const fontgen: FontConverter = .{
        .b = b,
        .exe = mkfont_exe,
    };

    const converter = mkicon.Converter.create(b, mkicon_dep);

    const desktop_icon_conv_options: mkicon.ConvertOptions = .{
        .geometry = .{ 32, 32 },
    };

    const tool_icon_conv_options: mkicon.ConvertOptions = .{
        .geometry = .{ 16, 16 },
    };

    const assets = b.path("../../assets");

    const rootfs = RootFS{ .write_file = b.addNamedWriteFiles("assets") };

    // Fonts:
    rootfs.install(
        "system/fonts/mono-6.font",
        fontgen.convert(assets.path(b, "fonts/mono-6/mono-6.font.json")),
    );
    rootfs.install(
        "system/fonts/mono-8.font",
        fontgen.convert(assets.path(b, "fonts/mono-6/mono-6.font.json")),
    );
    rootfs.install(
        "system/fonts/sans-6.font",
        fontgen.convert(assets.path(b, "fonts/mono-6/mono-6.font.json")),
    );
    rootfs.install(
        "system/fonts/sans.font",
        fontgen.convert(assets.path(b, "fonts/mono-6/mono-6.font.json")),
    );

    // Icons:
    rootfs.install(
        "system/icons/back.abm",
        converter.convert(assets.path(b, "icons/system/back.png"), "back.abm", tool_icon_conv_options),
    );
    rootfs.install(
        "system/icons/forward.abm",
        converter.convert(assets.path(b, "icons/system/forward.png"), "forward.abm", tool_icon_conv_options),
    );
    rootfs.install(
        "system/icons/reload.abm",
        converter.convert(assets.path(b, "icons/system/refresh.png"), "reload.abm", tool_icon_conv_options),
    );
    rootfs.install(
        "system/icons/home.abm",
        converter.convert(assets.path(b, "icons/system/home.png"), "home.abm", tool_icon_conv_options),
    );
    rootfs.install(
        "system/icons/go.abm",
        converter.convert(assets.path(b, "icons/system/go.png"), "go.abm", tool_icon_conv_options),
    );
    rootfs.install(
        "system/icons/stop.abm",
        converter.convert(assets.path(b, "icons/system/stop.png"), "stop.abm", tool_icon_conv_options),
    );
    rootfs.install(
        "system/icons/menu.abm",
        converter.convert(assets.path(b, "icons/system/menu.png"), "menu.abm", tool_icon_conv_options),
    );
    rootfs.install(
        "system/icons/plus.abm",
        converter.convert(assets.path(b, "icons/system/plus.png"), "plus.abm", tool_icon_conv_options),
    );
    rootfs.install(
        "system/icons/delete.abm",
        converter.convert(assets.path(b, "icons/system/delete.png"), "delete.abm", tool_icon_conv_options),
    );
    rootfs.install(
        "system/icons/copy.abm",
        converter.convert(assets.path(b, "icons/system/copy.png"), "copy.abm", tool_icon_conv_options),
    );
    rootfs.install(
        "system/icons/cut.abm",
        converter.convert(assets.path(b, "icons/system/cut.png"), "cut.abm", tool_icon_conv_options),
    );
    rootfs.install(
        "system/icons/paste.abm",
        converter.convert(assets.path(b, "icons/system/paste.png"), "paste.abm", tool_icon_conv_options),
    );

    rootfs.install(
        "system/icons/default-app-icon.abm",
        converter.convert(assets.path(b, "icons/apps/default-app-icon.png"), "menu.abm", desktop_icon_conv_options),
    );
}

const RootFS = struct {
    write_file: *std.Build.Step.WriteFile,

    pub fn install(rootfs: RootFS, path: []const u8, source: std.Build.LazyPath) void {
        _ = rootfs.write_file.addCopyFile(source, path);
    }
};

const FontConverter = struct {
    b: *std.Build,
    exe: *std.Build.Step.Compile,

    pub fn convert(fc: FontConverter, src: std.Build.LazyPath) std.Build.LazyPath {
        const run = fc.b.addRunArtifact(fc.exe);

        const output = run.addPrefixedOutputFileArg(
            "--output=",
            "converted.font",
        );

        run.addFileArg(src);

        return output;
    }
};
