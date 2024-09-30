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

const AppList = std.BoundedArray(App, 15);

var apps: AppList = .{};
var selected_app: ?AppInfo = null;
var last_click: Point = undefined;

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
