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
    app_loop: while (true) {
        while (ashet.ui.pollEvent(window)) |event| {
            switch (event) {
                .none => {},
                .mouse => |data| {
                    switch (data.type) {
                        .button_press => if (data.button == .left) {
                            painting = true;
                        },
                        .button_release => if (data.button == .left) {
                            painting = false;
                        },
                        .motion => if (painting) {
                            window.pixels[data.y * window.stride + data.x] = ashet.ui.ColorIndex.get(0xF);
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
        ashet.process.yield();
    }
}
