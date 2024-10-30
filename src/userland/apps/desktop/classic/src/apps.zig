//!
//! This file implements means to find applications
//! the user can start.
//!

const std = @import("std");
const ashet = @import("ashet");

const logger = std.log.scoped(.apps);

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
        if (ent.attributes.directory)
            continue;

        const name = ent.getName();

        if (!std.mem.endsWith(u8, name, ".ashex")) {
            logger.warn("ignore '{s}' from /apps", .{name});
            continue;
        }

        logger.info("app: {s}", .{ent.getName()});

        var app_file = try apps_dir.openFile(name, .read_only, .open_existing);
        defer app_file.close();

        // , &pal_off
        load_app(app_file, ent.name) catch |err| {
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

pub fn iterate(target_size: ashet.abi.Size) AppIterator {
    return .{
        .target_size = target_size,
        .bounds = .{
            .x = AppIterator.margin,
            .y = AppIterator.margin,
            .width = icon_size.width,
            .height = icon_size.height,
        },
    };
}

pub fn app_from_point(target_size: ashet.abi.Size, query: ashet.abi.Point) ?DesktopIcon {
    var iter = iterate(target_size);
    while (iter.next()) |app| {
        if (app.bounds.contains(query))
            return app;
    }
    return null;
}

pub const DesktopIcon = struct {
    app: *const App,
    bounds: ashet.abi.Rectangle,
    index: usize,
    icon: ashet.graphics.Framebuffer,
};

pub const AppIterator = struct {
    const margin = 8;
    const padding = 8;

    index: usize = 0,
    bounds: ashet.abi.Rectangle,
    target_size: ashet.abi.Size,

    pub fn next(self: *AppIterator) ?DesktopIcon {
        const right_limit = self.target_size.width - self.bounds.width - padding - margin;

        if (self.index >= list.items.len)
            return null;

        const info = DesktopIcon{
            .app = &list.items[self.index],
            .index = self.index,
            .bounds = self.bounds,
            .icon = list.items[self.index].icon orelse default_icon,
        };
        self.index += 1;

        self.bounds.x += (icon_size.width + padding);
        if (self.bounds.x >= right_limit) {
            self.bounds.x = margin;
            self.bounds.y += (icon_size.height + padding);
        }

        return info;
    }
};

fn load_app(file: ashet.fs.File, file_name: [ashet.abi.max_file_name_len]u8) !void {
    // , pal_offset: *u8

    const icon_byte_size, const icon_offset = blk: {
        var header_chunk: [512]u8 = undefined;

        if (try file.read(0, &header_chunk) != 512)
            return error.InvalidFile;

        var fbs = std.io.fixedBufferStream(&header_chunk);

        const reader = fbs.reader();
        var magic: [4]u8 = undefined;
        try reader.readNoEof(&magic);
        if (!std.mem.eql(u8, &magic, "ASHX"))
            return error.InvalidFile;

        const version = try reader.readInt(u8, .little);
        if (version != 0)
            return error.InvalidVersion;
        const file_type = try reader.readInt(u8, .little);
        if (file_type != 0)
            return error.InvalidFileType;

        const platform = try reader.readInt(u8, .little);
        _ = platform;

        try reader.skipBytes(1, .{});

        const icon_byte_size = try reader.readInt(u32, .little);
        const icon_offset = try reader.readInt(u32, .little);

        break :blk .{ icon_byte_size, icon_offset };
    };

    const app = list.addOne() catch {
        logger.warn("The system can only handle {} apps right now, but more are installed.", .{list.items.len});
        return;
    };
    errdefer _ = list.pop();

    const file_name_str = std.mem.sliceTo(&file_name, 0);

    // pal_offset.* -= 15;
    // errdefer pal_offset.* += 15;
    app.* = App{
        .disk_name_buffer = file_name,
        .display_name_buffer = file_name,
        .icon = null,
    };

    @memset(app.display_name_buffer[ file_name_str.len - ".ashex".len..], 0);

    if (icon_byte_size != 0) {
        app.icon = ashet.graphics.load_bitmap_file_at(file, icon_offset) catch |err| blk: {
            logger.warn("Failed to load icon for application {s}: {s}", .{
                std.mem.sliceTo(&file_name, 0),
                @errorName(err),
            });
            break :blk null;
        };
    } else {
        logger.warn("Application {s} does not have an icon. Using default.", .{std.mem.sliceTo(&file_name, 0)});
    }
}

// fn paint() void {
//     const font = gui.Font.fromSystemFont("sans-6", .{}) catch gui.Font.default;

//     var iter = AppIterator.init();
//     while (iter.next()) |info| {
//         const app = info.app;

//         const title = app.getName();

//         var total_bounds = info.bounds;
//         total_bounds.height += 8; // TODO: font size
//         if (!isTainted(total_bounds))
//             continue;

//         if (idOrNull(selected_app) == info.index) {
//             framebuffer.blit(Point.new(info.bounds.x - 1, info.bounds.y - 1), dither_grid);
//         }

//         framebuffer.blit(info.bounds.position(), app.icon.bitmap());

//         const width = font.measureWidth(title);

//         framebuffer.drawString(
//             info.bounds.x + Icon.width / 2 - width / 2,
//             info.bounds.y + Icon.height,
//             title,
//             &font,
//             ColorIndex.get(0x0),
//             width,
//         );
//     }
// }

// const dither_grid = blk: {
//     @setEvalBranchQuota(4096);
//     var buffer: [Icon.height + 2][Icon.width + 2]ColorIndex = undefined;
//     for (&buffer, 0..) |*row, y| {
//         for (row, 0..) |*c, x| {
//             c.* = if ((y + x) % 2 == 0) ColorIndex.get(0x01) else ColorIndex.get(0x00);
//         }
//     }
//     const buffer_copy = buffer;
//     break :blk Bitmap{
//         .width = Icon.width + 2,
//         .height = Icon.height + 2,
//         .stride = Icon.width + 2,
//         .pixels = @as([*]const ColorIndex, @ptrCast(&buffer_copy)),
//         .transparent = ColorIndex.get(0x01),
//     };
// };
