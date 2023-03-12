//!
//! A truly tiny browser for the interwebz.
//!
//! Supported protocols:
//! - gopher
//! - gemini
//! - http/s
//! - spartan
//! - finger
//!
//! Supported file formats:
//! - text/plain
//! - text/gemini
//! - text/html
//!

const std = @import("std");
const ashet = @import("ashet");
const gui = @import("ashet-gui");
const system_assets = @import("system-assets");

const ColorIndex = ashet.abi.ColorIndex;

pub usingnamespace ashet.core;

var tb_url_field_backing: [64]u8 = undefined;
var tb_passwd_backing: [64]u8 = undefined;

var interface = gui.Interface{ .widgets = &widgets };

const icons = struct {
    const back = gui.Bitmap.embed(system_assets.@"back.abm").bitmap;
    const forward = gui.Bitmap.embed(system_assets.@"forward.abm").bitmap;
    const reload = gui.Bitmap.embed(system_assets.@"reload.abm").bitmap;
    const home = gui.Bitmap.embed(system_assets.@"home.abm").bitmap;
    const go = gui.Bitmap.embed(system_assets.@"go.abm").bitmap;
    const stop = gui.Bitmap.embed(system_assets.@"stop.abm").bitmap;
    const menu = gui.Bitmap.embed(system_assets.@"menu.abm").bitmap;
};

var address_bar_buffer: [1024]u8 = undefined;

var widgets = [_]gui.Widget{
    gui.Panel.new(5, 5, 172, 57), // 0: coolbar
    gui.ToolButton.new(69, 42, icons.back), // 1: coolbar: backward
    gui.ToolButton.new(69, 42, icons.forward), // 2: coolbar: forward
    gui.ToolButton.new(69, 42, icons.reload), // 3: coolbar: reload
    gui.ToolButton.new(69, 42, icons.home), // 4: coolbar: home
    gui.TextBox.new(69, 42, 100, &address_bar_buffer, "") catch unreachable, // 5: coolbar: address
    gui.ToolButton.new(69, 42, icons.go), // 6: coolbar: go
    gui.ToolButton.new(69, 42, icons.menu), // 7: coolbar: app menu
    gui.ScrollBar.new(0, 0, .vertical, 100, 1000), // 8: scrollbar
};

fn initWidgets() !void {
    widgets[1].control.tool_button.clickEvent = gui.Event.new(gui.EventID.from(.coolbar_backward));
    widgets[2].control.tool_button.clickEvent = gui.Event.new(gui.EventID.from(.coolbar_forward));
    widgets[3].control.tool_button.clickEvent = gui.Event.new(gui.EventID.from(.coolbar_reload));
    widgets[4].control.tool_button.clickEvent = gui.Event.new(gui.EventID.from(.coolbar_home));
    // widgets[5].control.text_box.clickEvent = gui.Event.new(gui.EventID.from(.coolbar_address));
    widgets[6].control.tool_button.clickEvent = gui.Event.new(gui.EventID.from(.coolbar_go));
    widgets[7].control.tool_button.clickEvent = gui.Event.new(gui.EventID.from(.coolbar_app_menu));
}

pub fn main() !void {
    try initWidgets();

    const window = try ashet.ui.createWindow(
        "Gateway",
        ashet.abi.Size.new(182, 127),
        ashet.abi.Size.max,
        ashet.abi.Size.new(182, 127),
        .{ .popup = false },
    );
    defer ashet.ui.destroyWindow(window);

    layout(window);

    paint(window);

    app_loop: while (true) {
        const event = ashet.ui.getEvent(window);
        switch (event) {
            .mouse => |data| {
                if (interface.sendMouseEvent(data)) |guievt|
                    handleEvent(guievt);
                paint(window);
            },
            .keyboard => |data| {
                if (interface.sendKeyboardEvent(data)) |guievt|
                    handleEvent(guievt);
                paint(window);
            },
            .window_close => break :app_loop,
            .window_minimize => {},
            .window_restore => {},
            .window_moving => {},
            .window_moved => {},
            .window_resizing => {
                layout(window);
                paint(window);
            },
            .window_resized => {
                layout(window);
                paint(window);
            },
        }
    }
}

fn handleEvent(evt: gui.Event) void {
    switch (evt.id) {
        gui.EventID.from(.coolbar_backward) => std.log.info("gui.EventID.from(.coolbar_backward)", .{}),
        gui.EventID.from(.coolbar_forward) => std.log.info("gui.EventID.from(.coolbar_forward)", .{}),
        gui.EventID.from(.coolbar_reload) => std.log.info("gui.EventID.from(.coolbar_reload)", .{}),
        gui.EventID.from(.coolbar_home) => std.log.info("gui.EventID.from(.coolbar_home)", .{}),
        gui.EventID.from(.coolbar_go) => std.log.info("gui.EventID.from(.coolbar_go)", .{}),
        gui.EventID.from(.coolbar_app_menu) => std.log.info("gui.EventID.from(.coolbar_app_menu)", .{}),
        else => std.log.info("unhandled gui event: {}\n", .{evt}),
    }
}

fn newRect(x: i15, y: i15, w: u16, h: u16) ashet.abi.Rectangle {
    return ashet.abi.Rectangle{
        .x = x,
        .y = y,
        .width = w,
        .height = h,
    };
}

fn layout(window: *const ashet.ui.Window) void {
    const size = window.client_rectangle.size();

    widgets[0].bounds = newRect(0, 0, size.width, 24);

    widgets[1].bounds = newRect(3, 3, 18, 18); // 1: coolbar: backward
    widgets[2].bounds = newRect(23, 3, 18, 18); // 2: coolbar: forward
    widgets[3].bounds = newRect(43, 3, 18, 18); // 3: coolbar: reload
    widgets[4].bounds = newRect(63, 3, 18, 18); // 4: coolbar: home

    widgets[6].bounds = newRect(@intCast(u14, size.width) - 38 - 3, 3, 18, 18); // 6: coolbar: go
    widgets[7].bounds = newRect(@intCast(u14, size.width) - 18 - 3, 3, 18, 18); // 7: coolbar: app menu

    widgets[5].bounds = newRect(83, 6, @intCast(u15, widgets[6].bounds.x - 86), widgets[5].bounds.height); // 5: coolbar: address

    widgets[8].bounds = newRect(@intCast(i15, size.width - widgets[8].bounds.width), @intCast(i15, widgets[0].bounds.height), widgets[8].bounds.width, size.height - widgets[0].bounds.height - 10); // 8: scrollbar
}

fn paint(window: *const ashet.ui.Window) void {
    var fb = gui.Framebuffer.forWindow(window);

    fb.clear(ColorIndex.get(0));

    interface.paint(fb);

    ashet.ui.invalidate(window, newRect(0, 0, window.client_rectangle.width, window.client_rectangle.height));
}

fn udp_demo() !void {
    var socket = try ashet.net.Udp.open();
    defer socket.close();

    _ = try socket.bind(ashet.net.EndPoint.new(
        ashet.net.IP.ipv4(.{ 0, 0, 0, 0 }),
        8000,
    ));

    _ = try socket.sendTo(
        ashet.net.EndPoint.new(
            ashet.net.IP.ipv4(.{ 10, 0, 2, 2 }),
            4567,
        ),
        "Hello, World!\n",
    );

    while (true) {
        var buf: [256]u8 = undefined;
        var ep: ashet.net.EndPoint = undefined;
        const len = try socket.receiveFrom(&ep, &buf);
        if (len > 0) {
            std.log.info("received {s} from {}", .{ buf[0..len], ep });
        }
        ashet.process.yield();
    }
}
