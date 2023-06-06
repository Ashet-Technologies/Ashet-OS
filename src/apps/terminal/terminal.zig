const std = @import("std");
const ashet = @import("ashet");
const gui = @import("ashet-gui");
const system_assets = @import("system-assets");

pub usingnamespace ashet.core;

const widgets = struct {
    var new_tab_button: gui.Widget = gui.ToolButton.new(0, 0, gui.Bitmap.embed(system_assets.@"system/icons/plus.abm").bitmap);
    var copy_button: gui.Widget = gui.ToolButton.new(0, 0, gui.Bitmap.embed(system_assets.@"system/icons/copy.abm").bitmap);
    var cut_button: gui.Widget = gui.ToolButton.new(0, 0, gui.Bitmap.embed(system_assets.@"system/icons/cut.abm").bitmap);
    var paste_button: gui.Widget = gui.ToolButton.new(0, 0, gui.Bitmap.embed(system_assets.@"system/icons/paste.abm").bitmap);
    var menu_button: gui.Widget = gui.ToolButton.new(0, 0, gui.Bitmap.embed(system_assets.@"system/icons/menu.abm").bitmap);

    var coolbar_left: gui.Widget = gui.Panel.new(0, 0, 0, 0);
    var coolbar_clip: gui.Widget = gui.Panel.new(0, 0, 0, 0);
    var coolbar_right: gui.Widget = gui.Panel.new(0, 0, 0, 0);

    var tab_buttons: [16]gui.Widget = [1]gui.Widget{gui.Button.new(0, 28, 40, "")} ** 16;

    var shell_panel: gui.Widget = gui.Panel.new(0, 0, 200, 200);
};

const events = struct {
    const new_tab = gui.EventID.fromNumber(1);
    const clip_copy = gui.EventID.fromNumber(2);
    const clip_cut = gui.EventID.fromNumber(3);
    const clip_paste = gui.EventID.fromNumber(4);
    const open_menu = gui.EventID.fromNumber(5);
    const activate_tab = gui.EventID.fromNumber(6);
};

var gui_interface = gui.Interface{
    .widgets = &.{
        &widgets.shell_panel,
        &widgets.coolbar_left,
        &widgets.coolbar_clip,
        &widgets.coolbar_right,
        &widgets.new_tab_button,
        &widgets.copy_button,
        &widgets.cut_button,
        &widgets.paste_button,
        &widgets.menu_button,
        &widgets.tab_buttons[0],
        &widgets.tab_buttons[1],
        &widgets.tab_buttons[2],
        &widgets.tab_buttons[3],
        &widgets.tab_buttons[4],
        &widgets.tab_buttons[5],
        &widgets.tab_buttons[6],
        &widgets.tab_buttons[7],
        &widgets.tab_buttons[8],
        &widgets.tab_buttons[9],
        &widgets.tab_buttons[10],
        &widgets.tab_buttons[11],
        &widgets.tab_buttons[12],
        &widgets.tab_buttons[13],
        &widgets.tab_buttons[14],
        &widgets.tab_buttons[15],
    },
};

fn coolbarWidth(count: usize) u15 {
    return @intCast(u15, 8 + 20 * count + 8 * (@max(1, count) - 1));
}

fn doLayout(container: gui.Rectangle) void {
    widgets.coolbar_left.bounds = .{ .x = 0, .y = 0, .width = coolbarWidth(1), .height = 28 };
    widgets.coolbar_clip.bounds = .{ .x = coolbarWidth(1), .y = 0, .width = coolbarWidth(3), .height = 28 };
    widgets.coolbar_right.bounds = .{ .x = coolbarWidth(1) +| coolbarWidth(3), .y = 0, .width = container.width -| coolbarWidth(1) -| coolbarWidth(3), .height = 28 };

    widgets.new_tab_button.bounds = .{ .x = widgets.coolbar_left.bounds.x + 4, .y = 4, .width = 20, .height = 20 };
    widgets.copy_button.bounds = .{ .x = widgets.coolbar_clip.bounds.x + 4, .y = 4, .width = 20, .height = 20 };
    widgets.cut_button.bounds = .{ .x = widgets.coolbar_clip.bounds.x + 30, .y = 4, .width = 20, .height = 20 };
    widgets.paste_button.bounds = .{ .x = widgets.coolbar_clip.bounds.x + 58, .y = 4, .width = 20, .height = 20 };
    widgets.menu_button.bounds = .{ .x = widgets.coolbar_right.bounds.right() - 24, .y = 4, .width = 20, .height = 20 };

    var left: i16 = 0;
    for (&widgets.tab_buttons, tabs) |*button, tab| {
        if (!tab.active) {
            button.bounds.x = -10_000;
            continue;
        } else {
            button.bounds.x = left;
            left +|= @intCast(i16, button.bounds.width);

            button.control.button.text = tab.title;
        }
    }

    widgets.shell_panel.bounds = .{
        .x = 0,
        .y = 39,
        .width = container.width,
        .height = container.height -| 39,
    };
}

const Tab = struct {
    active: bool,
    title: []const u8,
};

var tabs: [16]Tab = [1]Tab{Tab{ .active = false, .title = "" }} ** 16;

pub fn main() !void {
    try gui.init();

    gui.Font.default = try gui.Font.fromSystemFont("sans-6", .{});

    widgets.new_tab_button.control.tool_button.clickEvent = gui.Event.new(events.new_tab);
    widgets.copy_button.control.tool_button.clickEvent = gui.Event.new(events.clip_copy);
    widgets.cut_button.control.tool_button.clickEvent = gui.Event.new(events.clip_cut);
    widgets.paste_button.control.tool_button.clickEvent = gui.Event.new(events.clip_paste);
    widgets.menu_button.control.tool_button.clickEvent = gui.Event.new(events.open_menu);

    for (&widgets.tab_buttons, 0..) |*button, index| {
        button.control.button.clickEvent = gui.Event.newTagged(events.activate_tab, @intToPtr(?*anyopaque, index));
    }

    const window = try ashet.ui.createWindow(
        "Connex",
        ashet.abi.Size.new(100, 50),
        ashet.abi.Size.max,
        ashet.abi.Size.new(200, 150),
        .{},
    );
    defer ashet.ui.destroyWindow(window);

    tabs[0] = .{
        .active = true,
        .title = "Shell",
    };
    tabs[1] = .{
        .active = true,
        .title = "COM1",
    };

    app_loop: while (true) {
        const event = ashet.ui.getEvent(window);
        switch (event) {
            .mouse => |input| {
                if (gui_interface.sendMouseEvent(input)) |gui_event| {
                    dispatchEvent(gui_event);
                }
            },
            .keyboard => |input| {
                if (gui_interface.sendKeyboardEvent(input)) |gui_event| {
                    dispatchEvent(gui_event);
                }
            },
            .window_close => break :app_loop,
            .window_minimize => {},
            .window_restore => {},
            .window_moving => {},
            .window_moved => {},
            .window_resizing => {
                doLayout(window.client_rectangle);
                paint(window);
            },
            .window_resized => {
                doLayout(window.client_rectangle);
                paint(window);
            },
        }
    }
}

fn paint(window: *const ashet.abi.Window) void {
    var fb = gui.Framebuffer.forWindow(window);

    gui_interface.paint(fb);

    ashet.ui.invalidate(window, .{ .x = 0, .y = 0, .width = window.client_rectangle.width, .height = window.client_rectangle.height });
}

fn dispatchEvent(event: gui.Event) void {
    switch (event.id) {
        events.new_tab => std.log.info("new_tab", .{}),
        events.clip_copy => std.log.info("clip_copy", .{}),
        events.clip_cut => std.log.info("clip_cut", .{}),
        events.clip_paste => std.log.info("clip_paste", .{}),
        events.open_menu => std.log.info("open_menu", .{}),
        events.activate_tab => std.log.info("activate_tab[{}]", .{@ptrToInt(event.tag)}),

        else => std.debug.panic("unexepceted event: {}", .{event.id}),
    }
}
