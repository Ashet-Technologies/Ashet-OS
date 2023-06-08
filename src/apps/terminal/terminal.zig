const std = @import("std");
const ashet = @import("ashet");
const fraxinus = @import("fraxinus");
const gui = @import("ashet-gui");
const system_assets = @import("system-assets");
const astd = @import("ashet-std");

pub usingnamespace ashet.core;

var widget_pool = astd.StaticPool(gui.Widget, 32){};

const MainWindow = struct {
    interface: gui.Interface,

    new_tab_button: gui.Widget,
    copy_button: gui.Widget,
    cut_button: gui.Widget,
    paste_button: gui.Widget,
    menu_button: gui.Widget,

    coolbar_left: gui.Widget,
    coolbar_clip: gui.Widget,
    coolbar_right: gui.Widget,

    shell_panel: gui.Widget,

    pub fn create(mw: *MainWindow) error{OutOfMemory}!void {
        mw.* = MainWindow{
            .interface = gui.Interface{},
            .new_tab_button = undefined,
            .copy_button = undefined,
            .cut_button = undefined,
            .paste_button = undefined,
            .menu_button = undefined,
            .coolbar_left = undefined,
            .coolbar_clip = undefined,
            .coolbar_right = undefined,
            .shell_panel = undefined,
        };

        mw.coolbar_left = gui.Panel.new(0, 0, 200, 200);
        mw.interface.appendWidget(&mw.coolbar_left);

        mw.coolbar_clip = gui.Panel.new(0, 0, 200, 200);
        mw.interface.appendWidget(&mw.coolbar_clip);

        mw.coolbar_right = gui.Panel.new(0, 0, 200, 200);
        mw.interface.appendWidget(&mw.coolbar_right);

        mw.shell_panel = gui.Panel.new(0, 0, 200, 200);
        mw.interface.appendWidget(&mw.shell_panel);

        mw.new_tab_button = gui.ToolButton.new(0, 0, comptime gui.Bitmap.embed(system_assets.@"system/icons/plus.abm").bitmap);
        mw.interface.appendWidget(&mw.new_tab_button);

        mw.copy_button = gui.ToolButton.new(0, 0, comptime gui.Bitmap.embed(system_assets.@"system/icons/copy.abm").bitmap);
        mw.interface.appendWidget(&mw.copy_button);

        mw.cut_button = gui.ToolButton.new(0, 0, comptime gui.Bitmap.embed(system_assets.@"system/icons/cut.abm").bitmap);
        mw.interface.appendWidget(&mw.cut_button);

        mw.paste_button = gui.ToolButton.new(0, 0, comptime gui.Bitmap.embed(system_assets.@"system/icons/paste.abm").bitmap);
        mw.interface.appendWidget(&mw.paste_button);

        mw.menu_button = gui.ToolButton.new(0, 0, comptime gui.Bitmap.embed(system_assets.@"system/icons/menu.abm").bitmap);
        mw.interface.appendWidget(&mw.menu_button);

        mw.shell_panel.overrides.can_focus = true;
        mw.new_tab_button.control.tool_button.clickEvent = gui.Event.new(events.new_tab);
        mw.copy_button.control.tool_button.clickEvent = gui.Event.new(events.clip_copy);
        mw.cut_button.control.tool_button.clickEvent = gui.Event.new(events.clip_cut);
        mw.paste_button.control.tool_button.clickEvent = gui.Event.new(events.clip_paste);
        mw.menu_button.control.tool_button.clickEvent = gui.Event.new(events.open_menu);
    }

    pub fn destroy(mw: *MainWindow) error{OutOfMemory}!MainWindow {
        widget_pool.destroy(mw.new_tab_button);
        widget_pool.destroy(mw.copy_button);
        widget_pool.destroy(mw.cut_button);
        widget_pool.destroy(mw.paste_button);
        widget_pool.destroy(mw.menu_button);
        widget_pool.destroy(mw.coolbar_left);
        widget_pool.destroy(mw.coolbar_clip);
        widget_pool.destroy(mw.coolbar_right);
        for (mw.tab_buttons) |tab| {
            widget_pool.destroy(tab);
        }
        widget_pool.destroy(mw.shell_panel);

        mw.* = undefined;
    }
};

const events = struct {
    const new_tab = gui.EventID.fromNumber(1);
    const clip_copy = gui.EventID.fromNumber(2);
    const clip_cut = gui.EventID.fromNumber(3);
    const clip_paste = gui.EventID.fromNumber(4);
    const open_menu = gui.EventID.fromNumber(5);
    const activate_tab = gui.EventID.fromNumber(6);
};

fn coolbarWidth(count: usize) u15 {
    return @intCast(u15, 8 + 20 * count + 8 * (@max(1, count) - 1));
}

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

const NewTabDialog = struct {
    window: *const ashet.abi.Window,
    event_iop: ashet.abi.ui.GetEvent,

    pub fn close(dlg: *NewTabDialog) void {
        ashet.io.cancel(&dlg.event_iop.iop);
        ashet.ui.destroyWindow(dlg.window);
        dlg.* = undefined;
    }
};

const App = struct {
    window: *const ashet.abi.Window,
    widgets: MainWindow,

    new_tab_dialog: ?NewTabDialog = null,

    tabs: std.BoundedArray(*Tab, @TypeOf(tab_pool).capacity) = .{},
    palette: Palette = default_palette,
    active_tab: ?*Tab = null,
    cursor_blink_visible: bool = false,

    pub fn paint(app: *App) void {
        var fb = gui.Framebuffer.forWindow(app.window);

        app.widgets.interface.paint(fb);

        app.paintTerminal();

        app.paintCursor();

        ashet.ui.invalidate(app.window, .{ .x = 0, .y = 0, .width = app.window.client_rectangle.width, .height = app.window.client_rectangle.height });
    }

    fn getTerminalSurface(app: App) gui.Rectangle {
        return gui.Rectangle{
            .x = app.widgets.shell_panel.bounds.x + 2,
            .y = app.widgets.shell_panel.bounds.y + 2,
            .width = app.widgets.shell_panel.bounds.width -| 4,
            .height = app.widgets.shell_panel.bounds.height -| 4,
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

    fn refreshTabs(app: *App) void {
        for (app.tabs.slice()) |tab| {
            tab.tab_button.control.button.toggle_active = (tab == app.active_tab);
        }
    }

    pub fn layout(app: *App) void {
        const container = app.window.client_rectangle;

        app.widgets.coolbar_left.bounds = .{ .x = 0, .y = 0, .width = coolbarWidth(1), .height = 28 };
        app.widgets.coolbar_clip.bounds = .{ .x = coolbarWidth(1), .y = 0, .width = coolbarWidth(3), .height = 28 };
        app.widgets.coolbar_right.bounds = .{ .x = coolbarWidth(1) +| coolbarWidth(3), .y = 0, .width = container.width -| coolbarWidth(1) -| coolbarWidth(3), .height = 28 };

        app.widgets.new_tab_button.bounds = .{ .x = app.widgets.coolbar_left.bounds.x + 4, .y = 4, .width = 20, .height = 20 };
        app.widgets.copy_button.bounds = .{ .x = app.widgets.coolbar_clip.bounds.x + 4, .y = 4, .width = 20, .height = 20 };
        app.widgets.cut_button.bounds = .{ .x = app.widgets.coolbar_clip.bounds.x + 30, .y = 4, .width = 20, .height = 20 };
        app.widgets.paste_button.bounds = .{ .x = app.widgets.coolbar_clip.bounds.x + 58, .y = 4, .width = 20, .height = 20 };
        app.widgets.menu_button.bounds = .{ .x = app.widgets.coolbar_right.bounds.right() - 24, .y = 4, .width = 20, .height = 20 };

        var left: i16 = 0;
        for (app.tabs.slice()) |tab| {
            tab.tab_button.bounds.x = left;
            left +|= @intCast(i16, tab.tab_button.bounds.width);
            tab.tab_button.control.button.text = tab.title;
        }

        app.widgets.shell_panel.bounds = .{
            .x = 0,
            .y = 39,
            .width = container.width,
            .height = container.height -| 39,
        };

        app.refreshTabs();
    }

    fn openNewTabDialog(app: *App) !void {
        var window = try ashet.ui.createWindow(
            "New Terminal",
            gui.Size.new(100, 200),
            gui.Size.new(100, 200),
            gui.Size.new(100, 200),
            .{ .popup = true },
        );
        errdefer ashet.ui.destroyWindow(window);

        app.spawnTab() catch |err| {
            std.log.err("failed to create tab: {s}", .{@errorName(err)});
        };

        app.new_tab_dialog = NewTabDialog{
            .window = window,
            .event_iop = ashet.abi.ui.GetEvent.new(.{ .window = window }),
        };

        _ = ashet.io.scheduleAndAwait(&app.new_tab_dialog.?.event_iop.iop, .schedule_only);
    }

    fn dispatchEvent(app: *App, event: gui.Event) void {
        switch (event.id) {
            events.new_tab => {
                if (app.new_tab_dialog != null)
                    return; // already open

                app.openNewTabDialog() catch |err| {
                    std.log.err("failed to open new tab dialog: {s}", .{@errorName(err)});
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
                const tab = @ptrCast(*Tab, @alignCast(@alignOf(Tab), event.tag));
                app.active_tab = tab;
                app.refreshTabs();
                app.paint();
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
        errdefer tab_pool.destroy(tab);

        try tab.init(ashet.process.allocator());
        errdefer tab.deinit();

        tab.title = "New Tab";

        app.tabs.appendAssumeCapacity(tab); // has the same size as the pool
        app.active_tab = tab;

        app.widgets.interface.appendWidget(&tab.tab_button);
    }

    fn handleUiEvent(app: *App, window: *const ashet.abi.Window, event: ashet.ui.Event) bool {
        switch (event) {
            .mouse => |input| {
                if (app.widgets.interface.sendMouseEvent(input)) |gui_event| {
                    app.dispatchEvent(gui_event);
                }
            },
            .keyboard => |input| {
                if (app.widgets.interface.focus == &app.widgets.shell_panel and app.active_tab != null) {
                    if (input.text) |text_ptr| {
                        const text = std.mem.sliceTo(text_ptr, 0);

                        if (input.pressed) {
                            app.active_tab.?.feed(text);
                            app.paintTerminal();
                        }
                    }
                } else if (app.widgets.interface.sendKeyboardEvent(input)) |gui_event| {
                    app.dispatchEvent(gui_event);
                }
            },
            .window_close => {
                if (app.new_tab_dialog != null and app.new_tab_dialog.?.window == window) {
                    app.new_tab_dialog.?.close();
                    app.new_tab_dialog = null;
                }
                return (window != app.window);
            },
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

var tab_pool = astd.StaticPool(Tab, 16){};

const Tab = struct {
    const Options = struct {
        echo: bool = false,
    };

    allocator: std.mem.Allocator,
    title: []const u8 = "",
    terminal: fraxinus.VirtualTerminal = undefined,
    backend: ComChannel = .none,
    options: Options = .{},
    tab_button: gui.Widget,

    pub fn init(tab: *Tab, allocator: std.mem.Allocator) !void {
        tab.* = Tab{
            .allocator = allocator,
            .title = "",
            .terminal = try fraxinus.VirtualTerminal.init(allocator, 80, 25),
            .tab_button = gui.Button.new(0, 28, 40, ""),
        };
        tab.tab_button.control.button.clickEvent = gui.Event.newTagged(events.activate_tab, tab);
    }

    pub fn deinit(tab: *Tab) void {
        tab.backend.deinit();
        tab.terminal.deinit(tab.allocator);
        tab.* = undefined;
    }

    pub fn feed(tab: *Tab, string: []const u8) void {
        if (tab.options.echo) {
            tab.terminal.write(string);
        }
        tab.backend.send(string) catch |err| {
            std.log.err("failed to send data to backend: {s}", .{@errorName(err)});
        };
    }
};

pub fn main() !void {
    try gui.init();

    gui.Font.default = try gui.Font.fromSystemFont("sans-6", .{});

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
        .widgets = undefined,
    };
    try app.widgets.create();
    errdefer {
        app.widgets.destroy();
        if (app.new_tab_dialog) |*dlg| {
            dlg.close();
        }
    }

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
                        if (event.check()) |_| {
                            const ui_event = ashet.ui.constructEvent(event.outputs.event_type, event.outputs.event);
                            if (!app.handleUiEvent(event.inputs.window, ui_event))
                                break :app_loop;
                        } else |err| {
                            std.log.err("failed to get app event: {s}", .{@errorName(err)});
                        }

                        _ = ashet.io.scheduleAndAwait(&main_window_event.iop, .schedule_only);
                    } else if (app.new_tab_dialog != null and event == &app.new_tab_dialog.?.event_iop) {
                        if (event.check()) |_| {
                            const ui_event = ashet.ui.constructEvent(event.outputs.event_type, event.outputs.event);
                            if (!app.handleUiEvent(event.inputs.window, ui_event))
                                break :app_loop;
                        } else |err| {
                            std.log.err("failed to get dialog event: {s}", .{@errorName(err)});
                        }

                        if (app.new_tab_dialog != null) {
                            // only run again when the window wasn't closed!
                            _ = ashet.io.scheduleAndAwait(&event.iop, .schedule_only);
                        }
                    } else {
                        @panic("unexpected iop!");
                    }
                },

                else => @panic("unexpected iop!"),
            }
        }
    }
}

const ComChannel = union(enum) {
    none,

    pub fn deinit(chan: *ComChannel) void {
        chan.* = undefined;
    }

    pub fn send(chan: *ComChannel, data: []const u8) !void {
        _ = chan;
        _ = data;
    }
};
