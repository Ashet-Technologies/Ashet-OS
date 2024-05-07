const std = @import("std");
const ashet_com = @import("os-common.zig");
const disk_image_step = @import("../../vendor/disk-image-step/build.zig");
const AssetBundleStep = @import("AssetBundleStep.zig");
const BitmapConverter = @import("BitmapConverter.zig");
const targets = @import("targets.zig");
const platforms = @import("platform.zig");

pub const App = struct {
    name: []const u8,
    exe: std.build.LazyPath,
    icon: ?std.build.LazyPath,
};

pub fn compileApps(
    ctx: *AshetContext,
    optimize: std.builtin.OptimizeMode,
    modules: ashet_com.Modules,
    ui_gen: *ashet_com.UiGenerator,
) void {
    ctx.createAshetApp("hello-world", "src/apps/hello-world.zig", null, optimize, &.{});

    {
        // const browser_assets = AssetBundleStep.create(b, ctx.rootfs);

        ctx.createAshetApp("browser", "src/apps/browser/browser.zig", "artwork/icons/small-icons/32x32-free-design-icons/32x32/Search online.png", optimize, &.{
            // .{
            //     .name = "assets",
            //     .module = b.createModule(.{
            //         .source_file = browser_assets.getOutput(),
            //         .dependencies = &.{},
            //     }),
            // },
            .{ .name = "hypertext", .module = modules.libhypertext },
            .{ .name = "main_window_layout", .module = ui_gen.render(.{ .path = ctx.b.pathFromRoot("src/apps/browser/main_window.lua") }) },
        });
    }

    ctx.createAshetApp("clock", "src/apps/clock/clock.zig", "artwork/icons/small-icons/32x32-free-design-icons/32x32/Time.png", optimize, &.{});
    ctx.createAshetApp("commander", "src/apps/commander/commander.zig", "artwork/icons/small-icons/32x32-free-design-icons/32x32/Folder.png", optimize, &.{});
    ctx.createAshetApp("editor", "src/apps/editor/editor.zig", "artwork/icons/small-icons/32x32-free-design-icons/32x32/Edit page.png", optimize, &.{});
    ctx.createAshetApp("music", "src/apps/music/music.zig", "artwork/icons/small-icons/32x32-free-design-icons/32x32/Play.png", optimize, &.{});
    ctx.createAshetApp("paint", "src/apps/paint/paint.zig", "artwork/icons/small-icons/32x32-free-design-icons/32x32/Painter.png", optimize, &.{});

    ctx.createAshetApp("terminal", "src/apps/terminal/terminal.zig", "artwork/icons/small-icons/32x32-free-design-icons/32x32/Tools.png", optimize, &.{
        .{ .name = "system-assets", .module = ui_gen.mod_system_assets },
        .{ .name = "fraxinus", .module = modules.fraxinus },
    });

    ctx.createAshetApp("gui-demo", "src/apps/gui-demo.zig", null, optimize, &.{});
    ctx.createAshetApp("font-demo", "src/apps/font-demo.zig", null, optimize, &.{});
    ctx.createAshetApp("net-demo", "src/apps/net-demo.zig", null, optimize, &.{});

    ctx.createAshetApp("wiki", "src/apps/wiki/wiki.zig", "artwork/icons/small-icons/32x32-free-design-icons/32x32/Help book.png", optimize, &.{
        .{ .name = "hypertext", .module = modules.libhypertext },
        .{ .name = "hyperdoc", .module = modules.hyperdoc },
        .{ .name = "ui-layout", .module = ui_gen.render(.{ .path = ctx.b.pathFromRoot("src/apps/wiki/ui.lua") }) },
    });

    {
        ctx.createAshetApp("dungeon", "src/apps/dungeon/dungeon.zig", "artwork/apps/dungeon/dungeon.png", optimize, &.{});
        // addBitmap(dungeon, bmpconv, "artwork/dungeon/floor.png", "src/apps/dungeon/data/floor.abm", .{ 32, 32 });
        // addBitmap(dungeon, bmpconv, "artwork/dungeon/wall-plain.png", "src/apps/dungeon/data/wall-plain.abm", .{ 32, 32 });
        // addBitmap(dungeon, bmpconv, "artwork/dungeon/wall-cobweb.png", "src/apps/dungeon/data/wall-cobweb.abm", .{ 32, 32 });
        // addBitmap(dungeon, bmpconv, "artwork/dungeon/wall-paper.png", "src/apps/dungeon/data/wall-paper.abm", .{ 32, 32 });
        // addBitmap(dungeon, bmpconv, "artwork/dungeon/wall-vines.png", "src/apps/dungeon/data/wall-vines.abm", .{ 32, 32 });
        // addBitmap(dungeon, bmpconv, "artwork/dungeon/wall-door.png", "src/apps/dungeon/data/wall-door.abm", .{ 32, 32 });
        // addBitmap(dungeon, bmpconv, "artwork/dungeon/wall-post-l.png", "src/apps/dungeon/data/wall-post-l.abm", .{ 32, 32 });
        // addBitmap(dungeon, bmpconv, "artwork/dungeon/wall-post-r.png", "src/apps/dungeon/data/wall-post-r.abm", .{ 32, 32 });
        // addBitmap(dungeon, bmpconv, "artwork/dungeon/enforcer.png", "src/apps/dungeon/data/enforcer.abm", .{ 32, 60 });
    }
}

pub const Mode = union(enum) {
    native: struct {
        platforms: platforms.PlatformData,
        platform: targets.Platform,
        rootfs: *disk_image_step.FileSystemBuilder,
    },
};

pub const AshetContext = struct {
    b: *std.build.Builder,
    bmpconv: BitmapConverter,
    mode: Mode,

    app_list: std.ArrayList(App),

    pub fn init(
        b: *std.build.Builder,
        bmpconv: BitmapConverter,
        mode: Mode,
    ) AshetContext {
        return AshetContext{
            .b = b,
            .bmpconv = bmpconv,
            .mode = mode,
            .app_list = std.ArrayList(App).init(b.allocator),
        };
    }

    fn createAshetApp(ctx: *AshetContext, name: []const u8, source: []const u8, maybe_icon: ?[]const u8, optimize: std.builtin.OptimizeMode, dependencies: []const std.Build.ModuleDependency) void {
        const target = switch (ctx.mode) {
            .native => |info| targets.getPlatformSpec(info.platform).target,
        };

        const exe = ctx.b.addExecutable(.{
            .name = ctx.b.fmt("{s}.app", .{name}),
            .root_source_file = .{ .path = source },
            .optimize = optimize,
            .target = target,
        });

        exe.omit_frame_pointer = false; // this is useful for debugging

        switch (ctx.mode) {
            .native => |info| {
                exe.linkLibrary(info.platforms.libsyscall.get(info.platform));

                exe.addModule("ashet", ctx.b.modules.get("ashet").?);
                exe.addModule("ashet-std", ctx.b.modules.get("ashet-std").?);
                exe.addModule("ashet-gui", ctx.b.modules.get("ashet-gui").?); // just add GUI to all apps by default *shrug*
                for (dependencies) |dep| {
                    exe.addModule(dep.name, dep.module);
                }

                exe.code_model = .small;
                exe.single_threaded = true; // AshetOS doesn't support multithreading in a modern sense
                exe.pie = true; // AshetOS requires PIE executables
                exe.force_pic = true; // which need PIC code
                exe.linkage = .dynamic;
                exe.strip = false;

                exe.setLinkerScriptPath(.{ .path = "src/libashet/application.ld" });

                const install = ctx.b.addInstallFileWithDir(
                    exe.getEmittedBin(),
                    .{ .custom = ctx.b.fmt("apps/{s}", .{@tagName(info.platform)}) }, // apps are the same *per platform*, not *per target*!
                    exe.name,
                );
                ctx.b.getInstallStep().dependOn(&install.step);

                info.rootfs.addFile(exe.getEmittedBin(), ctx.b.fmt("apps/{s}/code", .{name}));

                const icon_file = if (maybe_icon) |src_icon| blk: {
                    const icon_file = ctx.bmpconv.convert(
                        .{ .path = src_icon },
                        ctx.b.fmt("{s}.icon", .{name}),
                        .{
                            .geometry = .{ 32, 32 },
                            .palette = .{ .predefined = "src/kernel/data/palette.gpl" },
                            // .palette = .{ .sized = 15 },
                        },
                    );

                    info.rootfs.addFile(icon_file, ctx.b.fmt("apps/{s}/icon", .{name}));
                    break :blk icon_file;
                } else null;

                ctx.app_list.append(
                    App{
                        .name = name,
                        .exe = exe.getEmittedBin(),
                        .icon = icon_file,
                    },
                ) catch @panic("out of memory");
            },
        }
    }
};
