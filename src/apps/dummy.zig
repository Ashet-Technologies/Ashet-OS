const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

pub fn main() void {
    ashet.debug.write("Hello from App!\r\n");

    const ui = &ashet.syscalls().ui;

    const window = ui.createWindow(
        "Application",
        ashet.abi.Size.new(0, 0),
        ashet.abi.Size.new(400, 300),
        ashet.abi.Size.new(128, 128),
        .{ .popup = false },
    ) orelse return;
    defer ui.destroyWindow(window);

    while (true) {
        var data: ashet.abi.UiEvent = undefined;
        const event_type = ui.getEvent(window, &data);
        switch (event_type) {
            .none => {},
            .mouse => {},
            .keyboard => {},
            .window_close => break,
            .window_minimize => {},
            .window_restore => {},
            .window_moving => {},
            .window_moved => {},
            .window_resizing => {},
            .window_resized => {},
        }
        ashet.process.yield();
    }
}
