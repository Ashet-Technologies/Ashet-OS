const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

pub fn main() !void {
    const window = try ashet.ui.createWindow(
        "Clock",
        ashet.abi.Size.new(47, 47),
        ashet.abi.Size.new(47, 47),
        ashet.abi.Size.new(47, 47),
        .{ .popup = true },
    );
    defer ashet.ui.destroyWindow(window);

    for (window.pixels[0 .. window.stride * window.max_size.height]) |*c| {
        c.* = ashet.ui.ColorIndex.get(3);
    }

    var epoch_secs = std.time.epoch.EpochSeconds{ .secs = @intCast(u64, std.math.max(0, @divTrunc(ashet.time.nanoTimestamp(), std.time.ns_per_s))) };

    paint(window, epoch_secs);

    app_loop: while (true) {
        while (ashet.ui.pollEvent(window)) |event| {
            switch (event) {
                .none => {},
                .mouse => {},
                .keyboard => {},
                .window_close => break :app_loop,
                .window_minimize => {},
                .window_restore => {},
                .window_moving => {},
                .window_moved => {},
                .window_resizing => {},
                .window_resized => {},
            }
        }

        var next_step = std.time.epoch.EpochSeconds{ .secs = @intCast(u64, std.math.max(0, @divTrunc(ashet.time.nanoTimestamp(), std.time.ns_per_s))) };

        if (next_step.secs != epoch_secs.secs) {
            epoch_secs = next_step;
            paint(window, epoch_secs);
            ashet.ui.invalidate(window, ashet.ui.Rectangle.new(.{ .x = 0, .y = 0 }, window.client_rectangle.size()));
        }

        ashet.process.yield();
    }
}

const gui = @import("ashet-gui");

fn paint(window: *const ashet.ui.Window, time: std.time.epoch.EpochSeconds) void {
    var fb = gui.Framebuffer.forWindow(window);

    for (clock_face.pixels[0 .. clock_face.width * clock_face.height]) |color, i| {
        const x = @intCast(i16, i % clock_face.width);
        const y = @intCast(i16, i / clock_face.width);
        if (color != (comptime clock_face.transparent.?)) {
            fb.setPixel(1 + x, 1 + y, color);
            fb.setPixel(1 + x, 45 - y, color);
            fb.setPixel(45 - x, 1 + y, color);
            fb.setPixel(45 - x, 45 - y, color);
        }
    }

    const day_secs = time.getDaySeconds();

    const hour = day_secs.getHoursIntoDay();
    const minute = day_secs.getMinutesIntoHour();
    const seconds = day_secs.getSecondsIntoMinute();

    const H = struct {
        const digit = ashet.ui.ColorIndex.get(0);
        const shadow = ashet.ui.ColorIndex.get(10);
        const highlight = ashet.ui.ColorIndex.get(6);

        fn drawDigit(f: gui.Framebuffer, pos: u15, limit: u15, color: ashet.ui.ColorIndex, len: f32) void {
            const cx = @intCast(i16, f.width / 2);
            const cy = @intCast(i16, f.height / 2);

            const angle = std.math.tau * @intToFloat(f32, pos) / @intToFloat(f32, limit);

            const dx = @floatToInt(i16, len * @sin(angle));
            const dy = -@floatToInt(i16, len * @cos(angle));

            f.drawLine(
                gui.Point.new(cx, cy),
                gui.Point.new(cx + dx, cy + dy),
                color,
            );
        }
    };

    H.drawDigit(fb, minute + 60 * (@as(u15, hour) % 12), 12 * 60, H.digit, 9);
    H.drawDigit(fb, minute, 60, H.digit, 16);
    H.drawDigit(fb, seconds, 60, H.highlight, 19);
}

pub const clock_face = gui.Bitmap.parse(0,
    \\..................00000
    \\...............000FFFFF
    \\.............00FFFFFF00
    \\...........00FFFFFFFF00
    \\.........00FFFFFFFFFF00
    \\........0FFFFFFFFFFFFFF
    \\.......0FFF00FFFFFFFFFF
    \\......0FFFF00FFFFFFFFFF
    \\.....0FFFFFFFFFFFFFFFFF
    \\....0FFFFFFFFFFFFFFFFFF
    \\....0FFFFFFFFFFFFFFFFFF
    \\...0FFFFFFFFFFFFFFFFFFF
    \\...0FFFFFFFFFFFFFFFFFFF
    \\..0FF00FFFFFFFFFFFFFFFF
    \\..0FF00FFFFFFFFFFFFFFFF
    \\.0FFFFFFFFFFFFFFFFFFFFF
    \\.0FFFFFFFFFFFFFFFFFFFFF
    \\.0FFFFFFFFFFFFFFFFFFFFF
    \\0FFFFFFFFFFFFFFFFFFFFFF
    \\0FFFFFFFFFFFFFFFFFFFFFF
    \\0FFFFFFFFFFFFFFFFFFFFFF
    \\0F000FFFFFFFFFFFFFFFFFF
    \\0F000FFFFFFFFFFFFFFFFFF
);

fn parsedSpriteSize(comptime def: []const u8) ashet.ui.Size {
    @setEvalBranchQuota(100_000);
    var it = std.mem.split(u8, def, "\n");
    var first = it.next().?;
    const width = first.len;
    var height = 1;
    while (it.next()) |line| {
        std.debug.assert(line.len == width);
        height += 1;
    }
    return .{ .width = width, .height = height };
}

fn ParseResult(comptime def: []const u8) type {
    @setEvalBranchQuota(100_000);
    const size = parsedSpriteSize(def);
    return [size.height][size.width]?ashet.ui.ColorIndex;
}

fn parse(comptime def: []const u8) ParseResult(def) {
    @setEvalBranchQuota(100_000);

    const size = parsedSpriteSize(def);
    var icon: [size.height][size.width]?ashet.ui.ColorIndex = [1][size.width]?ashet.ui.ColorIndex{
        [1]?ashet.ui.ColorIndex{null} ** size.width,
    } ** size.height;

    var it = std.mem.split(u8, def, "\n");
    var y: usize = 0;
    while (it.next()) |line| : (y += 1) {
        var x: usize = 0;
        while (x < icon[0].len) : (x += 1) {
            icon[y][x] = if (std.fmt.parseInt(u8, line[x .. x + 1], 16)) |index|
                ashet.ui.ColorIndex.get(index)
            else |_|
                null;
        }
    }
    return icon;
}
