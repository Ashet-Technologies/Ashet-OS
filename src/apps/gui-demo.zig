const std = @import("std");
const ashet = @import("ashet");
const gui = @import("ashet-gui");

const ColorIndex = ashet.abi.ColorIndex;

pub usingnamespace ashet.core;

const events = struct {
    pub const cancel = @intToEnum(gui.EventID, 1);
    pub const login = @intToEnum(gui.EventID, 2);
};

var interface = gui.Interface{ .widgets = &widgets };
var widgets = blk: {
    var list = [_]gui.Widget{
        gui.Panel.new(5, 5, 172, 57),
        gui.Panel.new(5, 65, 172, 57),
        gui.Button.new(69, 42, null, "Cancel"),
        gui.Button.new(135, 42, null, "Login"),
        gui.TextBox.new(69, 14, 99, "xq"),
        gui.TextBox.new(69, 28, 99, "********"),
        gui.Label.new(15, 16, "Username:"),
        gui.Label.new(15, 30, "Password:"),
    };

    list[2].control.button.clickEvent = gui.Event.new(events.cancel);
    list[3].control.button.clickEvent = gui.Event.new(events.login);

    break :blk list;
};

pub fn main() !void {
    const window = try ashet.ui.createWindow(
        "GUI Demo",
        ashet.abi.Size.new(182, 127),
        ashet.abi.Size.new(182, 127),
        ashet.abi.Size.new(182, 127),
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
        events.cancel => {
            std.log.err("cancel was clicked", .{});
        },
        events.login => {
            std.log.err("login was clicked", .{});
        },
        else => std.log.info("unhandled gui event: {}\n", .{evt}),
    }
}

fn paint(window: *const ashet.ui.Window) void {
    var fb = gui.Framebuffer.forWindow(window);

    fb.clear(ColorIndex.get(0));

    interface.paint(fb);
}
