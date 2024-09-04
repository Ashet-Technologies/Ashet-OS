const std = @import("std");
const astd = @import("ashet-std");
const gui = @import("ashet-gui");
const logger = std.log.scoped(.ui);
const system_assets = @import("system-assets");
const libashet = @import("ashet");

const Size = ashet.abi.Size;
const Point = ashet.abi.Point;
const Rectangle = ashet.abi.Rectangle;
const ColorIndex = ashet.abi.ColorIndex;
const Color = ashet.abi.Color;
const Bitmap = gui.Bitmap;
const Framebuffer = gui.Framebuffer;

pub const Icon = struct {
    pub const width = 32;
    pub const height = 32;

    pixels: [height][width]ColorIndex, // 0 is transparent, 1…15 are indices into `palette`
    palette: [15]Color,

    pub fn bitmap(icon: *const Icon) Bitmap {
        return Bitmap{
            .width = width,
            .height = height,
            .stride = width,
            .pixels = @as([*]const ColorIndex, @ptrCast(&icon.pixels)),
            .transparent = ColorIndex.get(0xFF),
        };
    }

    pub fn load(stream: anytype, offset: u8) !Icon {
        var icon: Icon = undefined;

        var pixels: [height][width]u8 = undefined;

        const magic = try stream.readInt(u32, .little);
        if (magic != 0x48198b74)
            return error.InvalidFormat;

        const s_width = try stream.readInt(u16, .little);
        const s_height = try stream.readInt(u16, .little);
        if ((s_width != width) or (s_height != height))
            return error.InvalidDimension;

        const s_flags = try stream.readInt(u16, .little);
        const transparent = ((s_flags & 1) != 0);

        var palette_size: usize = try stream.readInt(u8, .little);
        if (palette_size == 0)
            palette_size = 256;
        // if (palette_size >= 16)
        //     return error.PaletteTooLarge;
        const transparency_key = try stream.readInt(u8, .little);

        try stream.readNoEof(std.mem.sliceAsBytes(&pixels));
        // try stream.readNoEof(std.mem.sliceAsBytes(icon.palette[0..palette_size]));

        for (pixels, 0..) |row, y| {
            for (row, 0..) |color, x| {
                icon.pixels[y][x] = if (transparent and color == transparency_key)
                    ColorIndex.get(0xFF)
                else
                    ColorIndex.get(offset + color);
            }
        }

        // for (icon.pixels) |row| {
        //     for (row) |c| {
        //         std.debug.assert(c == ColorIndex.get(0) or (c.index() >= offset and c.index() < offset + 15));
        //     }
        // }

        return icon;
    }
};

const default_icon = blk: {
    @setEvalBranchQuota(20_000);

    const data = system_assets.@"system/icons/default-app-icon.abm";

    var stream = std.io.fixedBufferStream(data);

    break :blk Icon.load(stream.reader(), framebuffer_default_icon_shift) catch @compileError("invalid icon format");

    // var icon = Icon{ .bitmap = undefined, .palette = undefined };
    // std.mem.copyForwards(u8, std.mem.sliceAsBytes(&icon.bitmap), data[0 .. 64 * 64]);
    // for (icon.palette) |*pal, i| {
    //     pal.* = @as(u16, pal_src[2 * i + 0]) << 0 |
    //         @as(u16, pal_src[2 * i + 1]) << 8;
    // }
    // break :blk icon;
};

const App = struct {
    name: [32]u8,
    icon: Icon,
    palette_base: u8,

    pub fn getName(app: *const App) []const u8 {
        return std.mem.sliceTo(&app.name, 0);
    }
};

const AppList = std.BoundedArray(App, 15);

var apps: AppList = .{};
var selected_app: ?AppInfo = null;
var last_click: Point = undefined;

const AppInfo = struct {
    app: *App,
    bounds: Rectangle,
    index: usize,
};
const AppIterator = struct {
    const padding = 8;

    index: usize = 0,
    bounds: Rectangle,

    pub fn init() AppIterator {
        return AppIterator{
            .bounds = Rectangle{
                .x = 8,
                .y = 8,
                .width = Icon.width,
                .height = Icon.height,
            },
        };
    }

    pub fn next(self: *AppIterator) ?AppInfo {
        const lower_limit = framebuffer.height - self.bounds.height - 8 - 4 - 11;

        if (self.index >= apps.len)
            return null;

        const info = AppInfo{
            .app = &apps.buffer[self.index],
            .index = self.index,
            .bounds = self.bounds,
        };
        self.index += 1;

        self.bounds.y += (Icon.height + padding);
        if (self.bounds.y >= lower_limit) {
            self.bounds.y = 8;
            self.bounds.x += (Icon.width + padding);
        }

        return info;
    }
};

fn init() void {
    reload() catch |err| {
        apps.len = 0;
        logger.err("failed to load desktop applications: {}", .{err});
    };
}

fn idOrNull(ai: ?AppInfo) ?usize {
    return if (ai) |a| a.index else null;
}

fn sendClick(point: Point) void {
    var iter = AppIterator.init();
    const selected = while (iter.next()) |info| {
        if (info.bounds.contains(point))
            break info;
    } else null;

    if (idOrNull(selected_app) != idOrNull(selected)) {
        last_click = point;
        if (selected_app) |ai| invalidateRegion(ai.bounds.grow(1));
        if (selected) |ai| invalidateRegion(ai.bounds.grow(1));
    } else if (selected_app) |app_info| {
        const app = &apps.buffer[app_info.index];
        if (last_click.manhattenDistance(point) < 2) {
            // logger.info("registered double click on app[{}]: {s}", .{ app_index, app.getName() });

            startApp(app.*) catch |err| logger.err("failed to start app {s}: {s}", .{ app.getName(), @errorName(err) });
        }
        last_click = point;
    }

    selected_app = selected;
}

fn startApp(app: App) !void {
    try ashet.apps.startApp(.{
        .name = app.getName(),
    });
}

fn paint() void {
    const font = gui.Font.fromSystemFont("sans-6", .{}) catch gui.Font.default;

    var iter = AppIterator.init();
    while (iter.next()) |info| {
        const app = info.app;

        const title = app.getName();

        var total_bounds = info.bounds;
        total_bounds.height += 8; // TODO: font size
        if (!isTainted(total_bounds))
            continue;

        if (idOrNull(selected_app) == info.index) {
            framebuffer.blit(Point.new(info.bounds.x - 1, info.bounds.y - 1), dither_grid);
        }

        framebuffer.blit(info.bounds.position(), app.icon.bitmap());

        const width = font.measureWidth(title);

        framebuffer.drawString(
            info.bounds.x + Icon.width / 2 - width / 2,
            info.bounds.y + Icon.height,
            title,
            &font,
            ColorIndex.get(0x0),
            width,
        );
    }
}

fn addApp(dir: libashet.fs.Directory, ent: ashet.abi.FileInfo, pal_offset: *u8) !void {
    const app = apps.addOne() catch {
        logger.warn("The system can only handle {} apps right now, but more are installed.", .{apps.len});
        return;
    };
    errdefer _ = apps.pop();

    // pal_offset.* -= 15;
    // errdefer pal_offset.* += 15;
    app.* = App{
        .name = undefined,
        .icon = undefined,
        .palette_base = pal_offset.*,
    };

    {
        const name = ent.getName();
        @memset(&app.name, 0);
        std.mem.copyForwards(u8, &app.name, name[0..@min(name.len, app.name.len)]);
    }

    if (dir.openFile("icon", .read_only, .open_existing)) |const_icon_file| {
        var icon_file = const_icon_file;
        defer icon_file.close();

        app.icon = Icon.load(icon_file.reader(), app.palette_base) catch |err| blk: {
            logger.warn("Failed to load icon for application {s}: {s}", .{
                ent.getName(),
                @errorName(err),
            });
            break :blk default_icon;
        };
    } else |_| {
        logger.warn("Application {s} does not have an icon. Using default.", .{ent.getName()});
        app.icon = default_icon;
    }
}

fn reload() !void {
    var apps_dir = try libashet.fs.Directory.openDrive(.system, "apps");
    defer apps_dir.close();

    apps.len = 0;
    var pal_off: u8 = framebuffer_default_icon_shift;

    while (try apps_dir.next()) |ent| {
        if (!ent.attributes.directory)
            continue;

        var app_dir = try apps_dir.openDir(ent.getName());
        defer app_dir.close();

        addApp(app_dir, ent, &pal_off) catch |err| {
            logger.err("failed to load application {s}: {s}", .{
                ent.getName(),
                @errorName(err),
            });
        };
    }

    logger.info("loaded apps:", .{});
    for (apps.slice(), 0..) |app, index| {
        logger.info("app[{}]: {s}", .{ index, app.getName() });
    }
}

const dither_grid = blk: {
    @setEvalBranchQuota(4096);
    var buffer: [Icon.height + 2][Icon.width + 2]ColorIndex = undefined;
    for (&buffer, 0..) |*row, y| {
        for (row, 0..) |*c, x| {
            c.* = if ((y + x) % 2 == 0) ColorIndex.get(0x01) else ColorIndex.get(0x00);
        }
    }
    const buffer_copy = buffer;
    break :blk Bitmap{
        .width = Icon.width + 2,
        .height = Icon.height + 2,
        .stride = Icon.width + 2,
        .pixels = @as([*]const ColorIndex, @ptrCast(&buffer_copy)),
        .transparent = ColorIndex.get(0x01),
    };
};
