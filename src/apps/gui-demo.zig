const std = @import("std");
const ashet = @import("ashet");
const gui = @import("ashet-gui");

const ColorIndex = ashet.abi.ColorIndex;

pub usingnamespace ashet.core;

var interface = gui.Interface{ .widgets = &widgets };
var widgets = [_]gui.Widget{
    gui.Button.new(16, 16, 48, "Hello"),
};

pub fn main() !void {
    const window = try ashet.ui.createWindow(
        "GUI Demo",
        ashet.abi.Size.new(200, 150),
        ashet.abi.Size.new(200, 150),
        ashet.abi.Size.new(200, 150),
        .{ .popup = false },
    );
    defer ashet.ui.destroyWindow(window);

    paint(window);

    app_loop: while (true) {
        while (ashet.ui.pollEvent(window)) |event| {
            switch (event) {
                .none => {},
                .mouse => |data| if (interface.sendMouseEvent(data)) |guievt| handleEvent(guievt),
                .keyboard => |data| if (interface.sendKeyboardEvent(data)) |guievt| handleEvent(guievt),
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

fn handleEvent(evt: gui.Event) void {
    switch (evt.id) {
        else => std.log.info("unhandled gui event: {}\n", .{evt}),
    }
}

fn paint(window: *const ashet.ui.Window) void {
    var fb = gui.Framebuffer.forWindow(window);

    fb.clear(ColorIndex.get(0));

    interface.paint(fb);
}
