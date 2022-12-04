const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

pub fn main() !void {
    const window = try ashet.ui.createWindow(
        "Paint",
        ashet.abi.Size.new(64, 64),
        ashet.abi.Size.new(400, 300),
        ashet.abi.Size.new(200, 150),
        .{},
    );
    defer ashet.ui.destroyWindow(window);

    for (window.pixels[0 .. window.stride * window.max_size.height]) |*c| {
        c.* = ashet.ui.ColorIndex.get(0);
    }

    var painting: bool = false;
    var mouse_x_prev: i16 = undefined;
    var mouse_y_prev: i16 = undefined;
    app_loop: while (true) {
        const event = ashet.ui.getEvent(window);
        switch (event) {
            .mouse => |data| {
                switch (data.type) {
                    .button_press => if (data.button == .left) {
                        painting = true;
                        mouse_x_prev = data.x;
                        mouse_y_prev = data.y;
                    },
                    .button_release => if (data.button == .left) {
                        painting = false;
                    },
                    .motion => if (painting) {
                        drawBresenhamLine(mouse_x_prev, mouse_y_prev, data.x, data.y, window);
                        mouse_x_prev = data.x;
                        mouse_y_prev = data.y;
                    },
                }
            },
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
}

pub fn drawBresenhamLine(
    x0: i16,
    y0: i16,
    x1: i16,
    y1: i16,
    window: *const ashet.ui.Window,
) void {
    var x = x0;
    var y = y0;
    var dx = abs(x1 - x0);
    var sx: i16 = if (x0 < x1) 1 else -1;
    var dy = -abs(y1 - y0);
    var sy: i16 = if (y0 < y1) 1 else -1;
    var err = dx + dy;

    while (true) {
        window.*.pixels[@intCast(usize, y) * window.stride + @intCast(usize, x)] = ashet.ui.ColorIndex.get(0xF);

        if (x0 == x1 and y0 == y1) break;

        const e2 = 2 * err;

        if (e2 >= dy) {
            if (x == x1) break;
            err = err + dy;
            x = x + sx;
        }

        if (e2 < dx) {
            if (y == y1) break;
            err = err + dx;
            y = y + sy;
        }
    }
}

fn abs(x: anytype) @TypeOf(x) {
    return if (x < 0) -x else x;
}
