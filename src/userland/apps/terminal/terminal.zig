const std = @import("std");
const ashet = @import("ashet");
const fraxinus = @import("fraxinus");
const gui = @import("ashet-gui");
const system_assets = @import("system-assets");
const astd = @import("ashet-std");

pub usingnamespace ashet.core;

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
        mw.new_tab_button.control.tool_button.clickEvent = gui.Event.new(events.open_dialog);
        mw.copy_button.control.tool_button.clickEvent = gui.Event.new(events.clip_copy);
        mw.cut_button.control.tool_button.clickEvent = gui.Event.new(events.clip_cut);
        mw.paste_button.control.tool_button.clickEvent = gui.Event.new(events.clip_paste);
        mw.menu_button.control.tool_button.clickEvent = gui.Event.new(events.open_menu);
    }

    pub fn destroy(mw: *MainWindow) void {
        mw.* = undefined;
    }
};

const NewTabWidgets = struct {
    interface: gui.Interface,

    ok_button: gui.Widget,
    cancel_button: gui.Widget,

    mode_select_field: gui.Widget,
    next_mode_button: gui.Widget,
    prev_mode_button: gui.Widget,

    widget_pool: astd.StaticPool(gui.Widget, 32) = .{},
    string_pool: astd.StaticPool([32]u8, 4) = .{},

    pub fn create(mw: *NewTabWidgets) error{OutOfMemory}!void {
        mw.* = NewTabWidgets{
            .interface = gui.Interface{},

            .ok_button = undefined,
            .cancel_button = undefined,

            .mode_select_field = undefined,
            .next_mode_button = undefined,
            .prev_mode_button = undefined,
        };

        mw.ok_button = gui.Button.new(0, 0, null, "Ok");
        mw.cancel_button = gui.Button.new(0, 0, null, "Cancel");

        mw.prev_mode_button = gui.Button.new(0, 0, null, "<");
        mw.mode_select_field = gui.Label.new(0, 0, "???");
        mw.next_mode_button = gui.Button.new(0, 0, null, ">");

        mw.ok_button.control.button.clickEvent = gui.Event.new(events.open_terminal);
        mw.cancel_button.control.button.clickEvent = gui.Event.new(events.close_dialog);

        mw.prev_mode_button.control.button.clickEvent = gui.Event.new(events.select_prev_mode);
        mw.next_mode_button.control.button.clickEvent = gui.Event.new(events.select_next_mode);
    }

    pub fn reset(mw: *NewTabWidgets, current_layout: ComChannelConfig) void {
        mw.widget_pool = .{};
        mw.string_pool = .{};

        mw.interface.widgets = .{};

        mw.interface.appendWidget(&mw.prev_mode_button);
        mw.interface.appendWidget(&mw.mode_select_field);
        mw.interface.appendWidget(&mw.next_mode_button);

        mw.interface.appendWidget(&mw.ok_button);
        mw.interface.appendWidget(&mw.cancel_button);

        mw.mode_select_field.control.label.text = @as(ComChannelType, current_layout).displayName();

        var y: i16 = mw.prev_mode_button.bounds.y + @as(u15, @intCast(mw.prev_mode_button.bounds.height));
        switch (current_layout) {
            inline else => |active_node| {
                const NodeType = @TypeOf(active_node);

                inline for (std.meta.fields(NodeType)) |fld| {
                    y +|= 4;

                    const label = mw.widget_pool.create() catch @panic("oof");
                    const editor = mw.widget_pool.create() catch @panic("oof");

                    label.* = gui.Label.new(4, y + 2, @field(com_channel_labels, fld.name));

                    const left_pos: u15 = 45;
                    const edit_width: u15 = 50;

                    const field_value = @field(active_node, fld.name);

                    const field_info = @typeInfo(fld.type);

                    editor.* = if (field_info == .Int) blk: {
                        var init_text: [10]u8 = undefined;
                        const str = std.fmt.bufPrint(&init_text, "{}", .{field_value}) catch @panic("out ");

                        break :blk gui.TextBox.new(left_pos, y, edit_width, mw.string_pool.create() catch @panic("increase string pool size"), str) catch unreachable;
                    } else switch (fld.type) {
                        bool => gui.CheckBox.new(left_pos, y, field_value),
                        []const u8 => gui.TextBox.new(left_pos, y, edit_width, mw.string_pool.create() catch @panic("increase string pool size"), field_value) catch unreachable,
                        else => @compileError(@typeName(fld.type) ++ " is not a supported editor type yet"),
                    };

                    mw.interface.appendWidget(label);
                    mw.interface.appendWidget(editor);

                    y += @as(u15, @intCast(label.bounds.height));
                }
                //
            },
        }
    }

    pub fn destroy(mw: *NewTabWidgets) void {
        mw.* = undefined;
    }

    pub fn layout(mw: *NewTabWidgets, rect: gui.Rectangle) void {
        mw.ok_button.bounds = .{ .x = @as(i16, @intCast(rect.width -| 4 -| 30)), .y = @as(i16, @intCast(rect.height -| 4 -| 11)), .width = 30, .height = 11 };
        mw.cancel_button.bounds = .{ .x = 4, .y = @as(i16, @intCast(rect.height -| 4 -| 11)), .width = 30, .height = 11 };

        mw.prev_mode_button.bounds = .{ .x = 4, .y = 4, .width = 11, .height = 11 };
        mw.mode_select_field.bounds = .{ .x = 4 + 11 + 4, .y = 6, .width = rect.width -| (4 * 4) -| (2 * 11), .height = 11 };
        mw.next_mode_button.bounds = .{ .x = @as(i16, @intCast(rect.width -| 4 -| 11)), .y = 4, .width = 11, .height = 11 };
    }
};

const events = struct {
    const open_dialog = gui.EventID.fromNumber(1);
    const clip_copy = gui.EventID.fromNumber(2);
    const clip_cut = gui.EventID.fromNumber(3);
    const clip_paste = gui.EventID.fromNumber(4);
    const open_menu = gui.EventID.fromNumber(5);
    const activate_tab = gui.EventID.fromNumber(6);

    const open_terminal = gui.EventID.fromNumber(7);
    const close_dialog = gui.EventID.fromNumber(8);
    const select_prev_mode = gui.EventID.fromNumber(9);
    const select_next_mode = gui.EventID.fromNumber(10);
};

fn coolbarWidth(count: usize) u15 {
    return @as(u15, @intCast(8 + 20 * count + 8 * (@max(1, count) - 1)));
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
    app: *App,
    window: *const ashet.abi.Window,
    widgets: NewTabWidgets,
    event_iop: ashet.abi.ui.GetEvent,

    com_channel_config: ComChannelConfig = .echo,

    pub fn close(dlg: *NewTabDialog) void {
        freeIopHandler(dlg.event_iop.iop.tag);
        ashet.io.cancel(&dlg.event_iop.iop);
        ashet.ui.destroyWindow(dlg.window);
        dlg.* = undefined;
    }

    pub fn paint(ntd: *NewTabDialog) void {
        var fb = gui.Framebuffer.forWindow(ntd.window);

        fb.clear(fb.pixels[0]);

        ntd.widgets.interface.paint(fb);

        ashet.ui.invalidate(ntd.window, .{ .x = 0, .y = 0, .width = ntd.window.client_rectangle.width, .height = ntd.window.client_rectangle.height });
    }

    pub fn layout(ntd: *NewTabDialog) void {
        const container = ntd.window.client_rectangle;
        ntd.widgets.layout(container);
        ntd.widgets.reset(ntd.com_channel_config);
    }

    fn handleUiEvent(ntd: *NewTabDialog, iop: *ashet.abi.ui.GetEvent) void {
        iop.check() catch |err| {
            std.log.err("failed to get ui event for new tab dialog: {s}", .{@errorName(err)});
            return;
        };
        const app = ntd.app;
        defer if (app.new_tab_dialog != null) {
            _ = ashet.io.scheduleAndAwait(&ntd.event_iop.iop, .schedule_only);
        };

        const event = ashet.ui.constructEvent(iop.outputs.event_type, iop.outputs.event);

        switch (event) {
            .mouse => |input| {
                if (ntd.widgets.interface.sendMouseEvent(input)) |gui_event| {
                    app.dispatchEvent(gui_event);
                }
            },
            .keyboard => |input| {
                if (ntd.widgets.interface.sendKeyboardEvent(input)) |gui_event| {
                    app.dispatchEvent(gui_event);
                }
            },
            .window_close => {
                ntd.close();
                app.new_tab_dialog = null;
            },
            .window_minimize => {},
            .window_restore => {},
            .window_moving => {},
            .window_moved => {},
            .window_resizing, .window_resized => {
                ntd.layout();
                ntd.paint();
            },
        }
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
        const fb = gui.Framebuffer.forWindow(app.window);

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
            .x = 2 + 6 * @as(i16, @intCast(cursor_pos.column)),
            .y = 2 + 8 * @as(i16, @intCast(cursor_pos.row)),
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
        app.widgets.menu_button.bounds = .{ .x = app.widgets.coolbar_right.bounds.right() -| 24, .y = 4, .width = 20, .height = 20 };

        var left: i16 = 0;
        for (app.tabs.slice()) |tab| {
            tab.tab_button.bounds.x = left;
            left +|= @as(i16, @intCast(tab.tab_button.bounds.width));
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
        const window = try ashet.ui.createWindow(
            "New Terminal",
            gui.Size.new(100, 130),
            gui.Size.new(100, 130),
            gui.Size.new(100, 130),
            .{ .popup = true },
        );
        errdefer ashet.ui.destroyWindow(window);

        app.new_tab_dialog = NewTabDialog{
            .app = app,
            .window = window,
            .event_iop = ashet.abi.ui.GetEvent.new(.{ .window = window }),
            .widgets = undefined,
        };

        const ntd = &app.new_tab_dialog.?;

        try ntd.widgets.create();
        ntd.layout();
        ntd.paint();

        try installIopHandler(*NewTabDialog, ntd, &ntd.event_iop, NewTabDialog.handleUiEvent);

        _ = ashet.io.scheduleAndAwait(&ntd.event_iop.iop, .schedule_only);
    }

    fn dispatchEvent(app: *App, event: gui.Event) void {
        switch (event.id) {
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
                const tab: *Tab = @ptrCast(@alignCast(event.tag));
                app.active_tab = tab;
                app.refreshTabs();
                app.paint();
            },

            events.open_dialog => {
                if (app.new_tab_dialog != null)
                    return; // already open

                app.openNewTabDialog() catch |err| {
                    std.log.err("failed to open new tab dialog: {s}", .{@errorName(err)});
                };
            },
            events.close_dialog => if (app.new_tab_dialog) |*ntd| {
                ntd.close();
                app.new_tab_dialog = null;
            },

            events.open_terminal => if (app.new_tab_dialog) |*ntd| {
                ntd.close();
                app.new_tab_dialog = null;

                app.spawnTab(ntd.com_channel_config) catch |err| {
                    std.log.err("failed to create tab: {s}", .{@errorName(err)});
                };
            },

            events.select_prev_mode => if (app.new_tab_dialog) |*ntd| {
                std.log.info("select_prev_mode", .{});
                ntd.com_channel_config = initDefaultComChannelConfig(
                    previousEnumValue(ntd.com_channel_config),
                );
                ntd.layout();
                ntd.paint();
            },
            events.select_next_mode => if (app.new_tab_dialog) |*ntd| {
                std.log.info("select_next_mode", .{});
                ntd.com_channel_config = initDefaultComChannelConfig(
                    nextEnumValue(ntd.com_channel_config),
                );
                ntd.layout();
                ntd.paint();
            },

            else => std.debug.panic("unexepceted event: {}", .{event.id}),
        }
    }

    fn spawnTab(app: *App, config: ComChannelConfig) !void {
        defer {
            app.layout();
            app.paint();
        }

        const tab: *Tab = try tab_pool.create();
        errdefer tab_pool.destroy(tab);

        try tab.init(ashet.process.allocator());
        errdefer tab.deinit();

        tab.title = try config.getName(tab.arena.allocator());

        app.tabs.appendAssumeCapacity(tab); // has the same size as the pool
        app.active_tab = tab;

        app.widgets.interface.appendWidget(&tab.tab_button);
    }

    fn handleUiEvent(app: *App, get_event: *ashet.abi.ui.GetEvent) void {
        get_event.check() catch |err| {
            std.log.err("failed to get ui event for main window: {s}", .{@errorName(err)});
            return;
        };

        const event = ashet.ui.constructEvent(get_event.outputs.event_type, get_event.outputs.event);

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
                shutdown_app_request = true;
            },
            .window_minimize => {},
            .window_restore => {},
            .window_moving => {},
            .window_moved => {},
            .window_resizing, .window_resized => {
                app.layout();
                app.paint();
            },
        }

        _ = ashet.io.scheduleAndAwait(&get_event.iop, .schedule_only);
    }

    const cursor_period = 600 * std.time.ns_per_ms;
    fn handleBlinkTimer(app: *App, timer: *ashet.abi.Timer) void {
        app.cursor_blink_visible = !app.cursor_blink_visible;
        timer.inputs.timeout += cursor_period;

        app.paintCursor();

        _ = ashet.io.scheduleAndAwait(&timer.iop, .schedule_only);
    }
};

var shutdown_app_request: bool = false;

var tab_pool = astd.StaticPool(Tab, 16){};

const Tab = struct {
    const Options = struct {
        echo: bool = false,
    };

    arena: std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,
    title: []const u8 = "",
    terminal: fraxinus.VirtualTerminal = undefined,
    com_channel: ComChannel = undefined,
    options: Options = .{},
    tab_button: gui.Widget,

    pub fn init(tab: *Tab, allocator: std.mem.Allocator) !void {
        tab.* = Tab{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .allocator = allocator,
            .title = "",
            .terminal = undefined,
            .tab_button = gui.Button.new(0, 28, 40, ""),
        };
        errdefer tab.arena.deinit();

        tab.terminal = try fraxinus.VirtualTerminal.init(tab.arena.allocator(), 80, 25);

        tab.tab_button.control.button.clickEvent = gui.Event.newTagged(events.activate_tab, tab);
    }

    pub fn deinit(tab: *Tab) void {
        tab.com_channel.deinit();
        tab.terminal.deinit(tab.allocator);
        tab.arena.deinit();
        tab.* = undefined;
    }

    pub fn feed(tab: *Tab, string: []const u8) void {
        if (tab.options.echo) {
            tab.terminal.write(string);
        }
        tab.com_channel.send(string) catch |err| {
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

    var main_window_event = ashet.abi.ui.GetEvent.new(.{ .window = window });
    var blink_timer_event = ashet.abi.Timer.new(.{ .timeout = ashet.time.nanoTimestamp() + App.cursor_period });

    try installIopHandler(*App, &app, &main_window_event, App.handleUiEvent);
    try installIopHandler(*App, &app, &blink_timer_event, App.handleBlinkTimer);

    _ = ashet.io.scheduleAndAwait(&main_window_event.iop, .schedule_only);
    _ = ashet.io.scheduleAndAwait(&blink_timer_event.iop, .schedule_only);

    app.layout();
    app.paint();

    app_loop: while (true) {
        const iop_list: ?*ashet.abi.IOP = ashet.io.scheduleAndAwait(null, .wait_one);

        var iter = ashet.io.iterate(iop_list);

        while (iter.next()) |iop| {
            if (iop.tag != 0) {
                IopHandler.invoke(iop);
            } else {
                std.log.err("received untagged iop: {s}", .{@tagName(iop.type)});
            }
        }

        if (shutdown_app_request)
            break :app_loop;
    }
}

var iop_handler_pool: astd.StaticPool(IopHandler, 32) = .{};

fn installIopHandler(comptime Context: type, context: Context, typed_iop: anytype, comptime handler: fn (context: Context, iop: @TypeOf(typed_iop)) void) !void {
    const handle = try createIopHandler(Context, @TypeOf(typed_iop.*), context, handler);
    errdefer freeIopHandler(handle);

    typed_iop.iop.tag = handle;
}

fn createIopHandler(comptime Context: type, comptime IOP: type, context: Context, comptime handler: fn (context: Context, iop: *IOP) void) !usize {
    const ptr = try iop_handler_pool.create();
    errdefer iop_handler_pool.destroy(ptr);
    ptr.* = IopHandler.create(Context, IOP, context, handler);
    return ptr.handle();
}

fn freeIopHandler(handle: usize) void {
    const handler = @as(*IopHandler, @ptrFromInt(handle));
    handler.* = undefined;
    iop_handler_pool.destroy(handler);
}

const IopHandler = struct {
    context: ?*anyopaque,
    handler: *const fn (context: ?*anyopaque, iop: *ashet.abi.IOP) void,

    pub fn create(comptime Context: type, comptime IOP: type, context: Context, comptime handler: fn (context: Context, iop: *IOP) void) IopHandler {
        const Wrapper = struct {
            fn handle(inner_context: ?*anyopaque, iop: *ashet.abi.IOP) void {
                handler(@as(Context, @ptrCast(@alignCast(inner_context))), ashet.abi.IOP.cast(IOP, iop));
            }
        };
        return IopHandler{
            .context = context,
            .handler = Wrapper.handle,
        };
    }

    pub fn invoke(iop: *ashet.abi.IOP) void {
        const iop_handler = @as(*IopHandler, @ptrFromInt(iop.tag));
        iop_handler.handler(iop_handler.context, iop);
    }

    pub fn handle(ioph: *IopHandler) usize {
        return @intFromPtr(ioph);
    }
};

const ComChannelType = enum {
    echo,
    tcp_stream,
    serial_port,
    console_server,

    pub fn displayName(cct: ComChannelType) []const u8 {
        return switch (cct) {
            .echo => "Echo",
            .tcp_stream => "TCP Stream",
            .serial_port => "Serial Port",
            .console_server => "Console Server",
        };
    }
};

const ComChannel = union(ComChannelType) {
    echo: Echo,
    tcp_stream: TcpStream,
    serial_port: SerialPort,
    console_server: ConsoleServer,

    pub fn deinit(chan: *ComChannel) void {
        chan.* = undefined;
    }

    pub fn send(chan: *ComChannel, data: []const u8) !void {
        _ = chan;
        _ = data;
    }

    pub const Echo = struct {
        //
    };
    pub const TcpStream = struct {
        //
    };
    pub const SerialPort = struct {
        //
    };
    pub const ConsoleServer = struct {
        //
    };
};

const com_channel_labels = .{
    .listen = "Listen:",
    .tls = "TLS:",
    .port = "Port:",
    .host = "Host:",
    .baud = "Baud:",
    .config = "Config:",
    .application = "App:",
};

const ComChannelConfig = union(ComChannelType) {
    echo: Echo,
    tcp_stream: TcpStream,
    serial_port: SerialPort,
    console_server: ConsoleServer,

    const Echo = struct {
        pub const Instance = ComChannel.Echo;

        //
    };
    const TcpStream = struct {
        pub const Instance = ComChannel.TcpStream;

        host: []const u8 = "127.0.0.1",
        listen: bool = false,
        port: u16 = 1337,
        tls: bool = false,
    };
    const SerialPort = struct {
        pub const Instance = ComChannel.SerialPort;

        port: []const u8 = "COM1",
        baud: u32 = 115_200,
        config: []const u8 = "8N1",
    };
    const ConsoleServer = struct {
        pub const Instance = ComChannel.ConsoleServer;

        application: []const u8 = "",
    };

    pub fn instantiate(ccc: ComChannelConfig, tab: *Tab) !void {
        return switch (@as(ComChannelType, ccc)) {
            inline else => |tag| {
                tab.com_channel = @unionInit(ComChannel, @tagName(tag), undefined);
                try @field(tab.com_channel, @tagName(tag)).create(@field(ccc, @tagName(tag)));
            },
        };
    }

    pub fn getName(ccc: ComChannelConfig, allocator: std.mem.Allocator) ![]const u8 {
        _ = allocator;
        return switch (ccc) {
            .echo => "Echo",
            .tcp_stream => "TCP",
            .serial_port => "Serial",
            .console_server => "Console",
        };
    }
};

fn previousEnumValue(val: ComChannelType) ComChannelType {
    const all_items = comptime std.enums.values(ComChannelType);
    const index = std.mem.indexOfScalar(ComChannelType, all_items, val).?;
    return all_items[(index + all_items.len - 1) % all_items.len];
}

fn nextEnumValue(val: ComChannelType) ComChannelType {
    const all_items = comptime std.enums.values(ComChannelType);
    const index = std.mem.indexOfScalar(ComChannelType, all_items, val).?;
    return all_items[(index + all_items.len + 1) % all_items.len];
}

fn initDefaultComChannelConfig(com_type: ComChannelType) ComChannelConfig {
    return switch (com_type) {
        inline else => |tag| @unionInit(ComChannelConfig, @tagName(tag), .{}),
    };
}
