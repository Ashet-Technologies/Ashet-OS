const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

pub fn main() !void {
    const window = try ashet.ui.createWindow(
        "Hyper Wiki",
        ashet.abi.Size.new(64, 64),
        ashet.abi.Size.max,
        ashet.abi.Size.new(200, 150),
        .{},
    );
    defer ashet.ui.destroyWindow(window);

    for (window.pixels[0 .. window.stride * window.max_size.height]) |*c| {
        c.* = ashet.ui.ColorIndex.get(0xF);
    }

    app_loop: while (true) {
        const event = ashet.ui.getEvent(window);
        switch (event) {
            .mouse => |data| {
                _ = data;
            },
            .keyboard => |data| {
                _ = data;
            },
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
