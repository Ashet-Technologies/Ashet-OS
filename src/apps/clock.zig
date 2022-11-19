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

    paint(window);

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
        ashet.process.yield();
    }
}

fn paint(window: *const ashet.ui.Window) void {
    for (clock_face) |row, y| {
        for (row) |pixel, x| {
            if (pixel) |color| {
                window.pixels[window.stride * (1 + y) + (1 + x)] = color;
                window.pixels[window.stride * (45 - y) + (1 + x)] = color;
                window.pixels[window.stride * (1 + y) + (45 - x)] = color;
                window.pixels[window.stride * (45 - y) + (45 - x)] = color;
            }
        }
    }

    const digit = ashet.ui.ColorIndex.get(0);
    const shadow = ashet.ui.ColorIndex.get(10);
    const highlight = ashet.ui.ColorIndex.get(6);

    // TODO: Paint digits

    _ = digit;
    _ = shadow;
    _ = highlight;
}

pub const clock_face = parse(
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