//!
//! This file implements means to find applications
//! the user can start.
//!

const std = @import("std");
const ashet = @import("ashet");

const logger = std.log.scoped(.apps);

const abi = ashet.abi;

pub const icon_size = ashet.abi.Size.new(32, 32);

pub const App = struct {
    disk_name_buffer: [ashet.abi.max_file_name_len]u8,
    display_name_buffer: [ashet.abi.max_file_name_len]u8,
    icon: ?ashet.graphics.Framebuffer,

    pub fn get_disk_name(self: *const App) []const u8 {
        return std.mem.sliceTo(&self.disk_name_buffer, 0);
    }

    pub fn get_display_name(self: *const App) []const u8 {
        return std.mem.sliceTo(&self.display_name_buffer, 0);
    }
};

var default_icon: ashet.graphics.Framebuffer = undefined;

var list: std.ArrayList(App) = undefined;

pub fn init() !void {
    list = std.ArrayList(App).init(ashet.process.mem.allocator());

    {
        var desktop_dir = try ashet.fs.Directory.openDrive(.system, "system/icons");
        defer desktop_dir.close();

        var default_icon_file = try desktop_dir.openFile("default-app-icon.abm", .read_only, .open_existing);
        defer default_icon_file.close();

        default_icon = try ashet.graphics.load_bitmap_file(default_icon_file);
    }

    try reload();
}

pub fn reload() !void {
    for (list.items) |app| {
        if (app.icon) |icon|
            icon.release();
    }
    list.shrinkRetainingCapacity(0);

    var apps_dir = try ashet.fs.Directory.openDrive(.system, "apps");
    defer apps_dir.close();

    // var pal_off: u8 = framebuffer_default_icon_shift;

    while (try apps_dir.next()) |ent| {
        if (!ent.attributes.directory)
            continue;

        var app_dir = try apps_dir.openDir(ent.getName());
        defer app_dir.close();

        // , &pal_off
        load_app(app_dir, ent) catch |err| {
            logger.err("failed to load application {s}: {s}", .{
                ent.getName(),
                @errorName(err),
            });
        };
    }

    logger.info("loaded apps:", .{});
    for (list.items, 0..) |app, index| {
        logger.info("app[{}]: disk='{s}', display='{s}'", .{ index, app.get_disk_name(), app.get_display_name() });
    }
}

fn load_app(dir: ashet.fs.Directory, ent: ashet.abi.FileInfo) !void {
    // , pal_offset: *u8
    const app = list.addOne() catch {
        logger.warn("The system can only handle {} apps right now, but more are installed.", .{list.items.len});
        return;
    };
    errdefer _ = list.pop();

    // pal_offset.* -= 15;
    // errdefer pal_offset.* += 15;
    app.* = App{
        .disk_name_buffer = ent.name,
        .display_name_buffer = ent.name,
        .icon = null,
    };

    if (dir.openFile("icon", .read_only, .open_existing)) |const_icon_file| {
        var icon_file = const_icon_file;
        defer icon_file.close();

        app.icon = ashet.graphics.load_bitmap_file(icon_file) catch |err| blk: {
            logger.warn("Failed to load icon for application {s}: {s}", .{
                ent.getName(),
                @errorName(err),
            });
            break :blk null;
        };
    } else |_| {
        logger.warn("Application {s} does not have an icon. Using default.", .{ent.getName()});
    }
}
