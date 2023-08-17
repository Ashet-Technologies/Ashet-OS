const std = @import("std");
const ashet = @import("ashet");
const gui = @import("ashet-gui");

pub usingnamespace ashet.core;

pub fn main() !void {
    try gui.init();

    const window = try ashet.ui.createWindow(
        "Font Demo",
        ashet.abi.Size.new(100, 40),
        ashet.abi.Size.new(400, 300),
        ashet.abi.Size.new(350, 55),
        .{ .popup = false },
    );
    defer ashet.ui.destroyWindow(window);

    paint(window);

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
            .window_resizing => paint(window),
            .window_resized => paint(window),
        }
    }
}

fn paint(window: *const ashet.ui.Window) void {
    var fb = gui.Framebuffer.forWindow(window);

    fb.clear(fb.pixels[0]);

    const font_names = [_][]const u8{
        "mono-6",
        "mono-8",
        "sans",
        "sans-6",
    };

    const demo_text = "The quick brown fox jumps over the lazy dog";

    var y: i16 = 4;

    for (font_names) |font_name| {
        var font = gui.Font.fromSystemFont(font_name, .{ .size = 12 }) catch continue;
        fb.drawString(4, y, demo_text, &font, @enumFromInt(gui.ColorIndex, 0), null);
        y += font.lineHeight();
        y += 2;
    }

    ashet.ui.invalidate(window, ashet.abi.Rectangle.new(ashet.abi.Point.zero, window.max_size));
}
