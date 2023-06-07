const std = @import("std");
const ashet = @import("ashet");
const fraxinus = @import("fraxinus");
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
        &widgets.shell_panel, // index 0
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

const Tab = struct {
    allocator: std.mem.Allocator,
    title: []const u8 = "",
    terminal: fraxinus.VirtualTerminal = undefined,

    pub fn init(allocator: std.mem.Allocator) !Tab {
        return Tab{
            .allocator = allocator,
            .title = "",
            .terminal = try fraxinus.VirtualTerminal.init(allocator, 80, 25),
        };
    }

    pub fn deinit(tab: *Tab) void {
        tab.terminal.deinit(tab.allocator);
        tab.* = undefined;
    }

    pub fn feed(tab: *Tab, string: []const u8) void {
        tab.terminal.write(string);
    }
};

const tab_pool = struct {
    const size = 16;

    var tab_storage: [16]Tab = undefined;

    var tab_alloc: std.bit_set.IntegerBitSet(size) = std.bit_set.IntegerBitSet(size).initFull();

    pub fn create() error{OutOfMemory}!*Tab {
        const index = tab_alloc.toggleFirstSet() orelse return error.OutOfMemory;
        errdefer tab_alloc.set(index);

        tab_storage[index] = try Tab.init(ashet.process.allocator());
        errdefer tab_storage[index].deinit();

        return &tab_storage[index];
    }

    pub fn destroy(tab: *Tab) void {
        const index = @divExact(@ptrToInt(tab) - @ptrToInt(&tab_storage), @sizeOf(Tab));
        std.debug.assert(index < tab_storage.len);
        std.debug.assert(!tab_alloc.isSet(index));
        tab_storage[index].deinit();
        tab_alloc.unset(index);
    }
};

const Palette = std.enums.EnumArray(fraxinus.Color, gui.ColorIndex);

const default_palette = blk: {
    var pal = Palette.initUndefined();
    pal.set(.black, gui.ColorIndex.get(0x00));
    pal.set(.red, gui.ColorIndex.get(0x04));
    pal.set(.green, gui.ColorIndex.get(0x06));
    pal.set(.blue, gui.ColorIndex.get(0x02));
    pal.set(.cyan, gui.ColorIndex.get(0x0E));
    pal.set(.magenta, gui.ColorIndex.get(0x0D));
    pal.set(.yellow, gui.ColorIndex.get(0x08));
    pal.set(.white, gui.ColorIndex.get(0x0F));
    break :blk pal;
};

const App = struct {
    window: *const ashet.abi.Window,
    tabs: std.BoundedArray(*Tab, tab_pool.size) = .{},
    palette: Palette = default_palette,
    active_tab: ?*Tab = null,
    cursor_blink_visible: bool = false,

    pub fn paint(app: *App) void {
        var fb = gui.Framebuffer.forWindow(app.window);

        gui_interface.paint(fb);

        app.paintTerminal();

        app.paintCursor();

        ashet.ui.invalidate(app.window, .{ .x = 0, .y = 0, .width = app.window.client_rectangle.width, .height = app.window.client_rectangle.height });
    }

    fn getTerminalSurface(app: App) gui.Rectangle {
        _ = app;
        return gui.Rectangle{
            .x = widgets.shell_panel.bounds.x + 2,
            .y = widgets.shell_panel.bounds.y + 2,
            .width = widgets.shell_panel.bounds.width -| 4,
            .height = widgets.shell_panel.bounds.height -| 4,
        };
    }

    pub fn paintTerminal(app: *App) void {
        const terminal_surface = app.getTerminalSurface();

        const font = gui.Font.fromSystemFont("mono-8", .{}) catch @panic("mono-8 font not found!");

        const glyph_w = 6;
        const glyph_h = 8;

        var fb = gui.Framebuffer.forWindow(app.window).view(terminal_surface);

        const background = app.palette.get(.black);
        fb.clear(background);

        if (app.active_tab) |tab| {
            const data = &tab.terminal.page;

            var pos_y: i16 = 2;
            for (0..data.height) |y| {
                var pos_x: i16 = 2;
                for (data.row(y)) |char| {
                    var str: [6]u8 = undefined;

                    const len = std.unicode.utf8Encode(std.math.cast(u21, char.codepoint) orelse '�', &str) catch @panic("invalid codepoint!");

                    const char_background = app.palette.get(char.attributes.background);
                    if (char_background != background) {
                        fb.fillRectangle(.{ .x = pos_x, .y = pos_y, .width = glyph_w, .height = glyph_h }, char_background);
                    }

                    fb.drawString(pos_x, pos_y, str[0..len], &font, app.palette.get(char.attributes.foreground), null);

                    pos_x += glyph_w;

                    if (pos_x >= fb.width)
                        break;
                }
                pos_y += glyph_h;
                if (pos_y >= fb.height)
                    break;
            }
        }

        ashet.ui.invalidate(app.window, terminal_surface);
    }

    pub fn paintCursor(app: *App) void {
        const tab = app.active_tab orelse return;

        const cursor_pos = tab.terminal.state.cursor;

        if (cursor_pos.column >= tab.terminal.page.width and cursor_pos.row >= tab.terminal.page.height)
            return;

        const terminal_surface = app.getTerminalSurface();

        var fb = gui.Framebuffer.forWindow(app.window).view(terminal_surface);

        var cursor_rect = gui.Rectangle{
            .x = 2 + 6 * @intCast(i16, cursor_pos.column),
            .y = 2 + 8 * @intCast(i16, cursor_pos.row),
            .width = 6,
            .height = 8,
        };

        if (app.cursor_blink_visible) {
            fb.fillRectangle(cursor_rect, app.palette.get(.white));
        } else {
            fb.fillRectangle(cursor_rect, app.palette.get(.black));
        }

        cursor_rect.x += terminal_surface.x;
        cursor_rect.y += terminal_surface.y;

        ashet.ui.invalidate(app.window, cursor_rect);
    }

    pub fn layout(app: *App) void {
        const container = app.window.client_rectangle;

        widgets.coolbar_left.bounds = .{ .x = 0, .y = 0, .width = coolbarWidth(1), .height = 28 };
        widgets.coolbar_clip.bounds = .{ .x = coolbarWidth(1), .y = 0, .width = coolbarWidth(3), .height = 28 };
        widgets.coolbar_right.bounds = .{ .x = coolbarWidth(1) +| coolbarWidth(3), .y = 0, .width = container.width -| coolbarWidth(1) -| coolbarWidth(3), .height = 28 };

        widgets.new_tab_button.bounds = .{ .x = widgets.coolbar_left.bounds.x + 4, .y = 4, .width = 20, .height = 20 };
        widgets.copy_button.bounds = .{ .x = widgets.coolbar_clip.bounds.x + 4, .y = 4, .width = 20, .height = 20 };
        widgets.cut_button.bounds = .{ .x = widgets.coolbar_clip.bounds.x + 30, .y = 4, .width = 20, .height = 20 };
        widgets.paste_button.bounds = .{ .x = widgets.coolbar_clip.bounds.x + 58, .y = 4, .width = 20, .height = 20 };
        widgets.menu_button.bounds = .{ .x = widgets.coolbar_right.bounds.right() - 24, .y = 4, .width = 20, .height = 20 };

        var left: i16 = 0;
        for (app.tabs.slice(), widgets.tab_buttons[0..app.tabs.len]) |tab, *button| {
            button.bounds.x = left;
            left +|= @intCast(i16, button.bounds.width);

            button.control.button.text = tab.title;
        }
        for (widgets.tab_buttons[app.tabs.len..]) |*button| {
            button.bounds.x = -10_000;
            button.control.button.text = "";
        }

        widgets.shell_panel.bounds = .{
            .x = 0,
            .y = 39,
            .width = container.width,
            .height = container.height -| 39,
        };
    }

    fn dispatchEvent(app: *App, event: gui.Event) void {
        switch (event.id) {
            events.new_tab => {
                app.spawnTab() catch |err| {
                    std.log.err("failed to create tab: {s}", .{@errorName(err)});
                };
            },
            events.clip_copy => {
                std.log.info("clip_copy", .{});
                if (app.active_tab) |tab| {
                    tab.terminal.write("Hello, World!");
                    tab.terminal.execute(.new_line);
                    app.paintTerminal();
                }
            },
            events.clip_cut => {
                std.log.info("clip_cut", .{});
                if (app.active_tab) |tab| {
                    tab.terminal.write("echo \"hi\"");
                    app.paintTerminal();
                }
            },
            events.clip_paste => {
                std.log.info("clip_paste", .{});
                if (app.active_tab) |tab| {
                    tab.terminal.execute(.line_feed);
                    app.paintTerminal();
                }
            },
            events.open_menu => std.log.info("open_menu", .{}),
            events.activate_tab => {
                const index = @ptrToInt(event.tag);
                if (index < app.tabs.len) {
                    app.active_tab = app.tabs.buffer[index];
                    app.paintTerminal();
                } else {
                    std.log.warn("clicked invalid tab: {}", .{index});
                }
            },

            else => std.debug.panic("unexepceted event: {}", .{event.id}),
        }
    }

    fn spawnTab(app: *App) !void {
        defer {
            app.layout();
            app.paint();
        }

        const tab = try tab_pool.create();
        errdefer tab_pool.destroy();

        tab.title = "New Tab";

        app.tabs.appendAssumeCapacity(tab); // has the same size as the pool
        app.active_tab = tab;
    }

    fn handleUiEvent(app: *App, event: ashet.ui.Event) bool {
        switch (event) {
            .mouse => |input| {
                if (gui_interface.sendMouseEvent(input)) |gui_event| {
                    app.dispatchEvent(gui_event);
                }
            },
            .keyboard => |input| {
                if ((gui_interface.focus orelse 1) == 0 and app.active_tab != null) {
                    if (input.text) |text_ptr| {
                        const text = std.mem.sliceTo(text_ptr, 0);

                        if (input.pressed) {
                            app.active_tab.?.feed(text);
                            app.paintTerminal();
                        }
                    }
                } else if (gui_interface.sendKeyboardEvent(input)) |gui_event| {
                    app.dispatchEvent(gui_event);
                }
            },
            .window_close => return false,
            .window_minimize => {},
            .window_restore => {},
            .window_moving => {},
            .window_moved => {},
            .window_resizing => {
                app.layout();
                app.paint();
            },
            .window_resized => {
                app.layout();
                app.paint();
            },
        }
        return true;
    }

    fn handleBlinkTimer(app: *App) void {
        app.cursor_blink_visible = !app.cursor_blink_visible;

        app.paintCursor();
    }
};

pub fn main() !void {
    try gui.init();

    widgets.shell_panel.overrides.can_focus = true;

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

    var app = App{
        .window = window,
    };

    const cursor_period = 600 * std.time.ns_per_ms;

    var main_window_event = ashet.abi.ui.GetEvent.new(.{ .window = window });
    var blink_timer_event = ashet.abi.Timer.new(.{ .timeout = ashet.time.nanoTimestamp() + cursor_period });

    _ = ashet.io.scheduleAndAwait(&main_window_event.iop, .schedule_only);
    _ = ashet.io.scheduleAndAwait(&blink_timer_event.iop, .schedule_only);

    app.layout();
    app.paint();

    app_loop: while (true) {
        var iop_list: ?*ashet.abi.IOP = ashet.io.scheduleAndAwait(null, .wait_one);

        var iter = ashet.io.iterate(iop_list);

        while (iter.next()) |iop| {
            switch (iop.type) {
                .timer => {
                    const timer = ashet.abi.IOP.cast(ashet.abi.Timer, iop);
                    if (timer == &blink_timer_event) {
                        app.handleBlinkTimer();

                        blink_timer_event.inputs.timeout += cursor_period;
                        _ = ashet.io.scheduleAndAwait(&blink_timer_event.iop, .schedule_only);
                    } else {
                        @panic("unexpected timre iop!");
                    }
                },

                .ui_get_event => {
                    const event = ashet.abi.IOP.cast(ashet.abi.ui.GetEvent, iop);

                    if (event == &main_window_event) {
                        if (main_window_event.check()) |_| {
                            if (!app.handleUiEvent(ashet.ui.constructEvent(main_window_event.outputs.event_type, main_window_event.outputs.event)))
                                break :app_loop;
                        } else |err| {
                            std.log.err("failed to get app event: {s}", .{@errorName(err)});
                        }

                        _ = ashet.io.scheduleAndAwait(&main_window_event.iop, .schedule_only);
                    } else {
                        @panic("unexpected iop!");
                    }
                },

                else => @panic("unexpected iop!"),
            }
        }
    }
}
