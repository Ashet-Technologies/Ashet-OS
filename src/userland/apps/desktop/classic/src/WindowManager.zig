const std = @import("std");
const astd = @import("ashet-std");
const ashet = @import("ashet");
const logger = std.log.scoped(.window_manager);

const WindowManager = @This();

const DamageTracking = @import("DamageTracking.zig");

const themes = @import("theme.zig");
const icons = @import("icons.zig");

const Size = ashet.abi.Size;
const Point = ashet.abi.Point;
const Rectangle = ashet.abi.Rectangle;
const ColorIndex = ashet.abi.ColorIndex;
const Color = ashet.abi.Color;

const WindowEvent = union(ashet.abi.WindowEvent.Type) {
    widget_notify: ashet.abi.WidgetNotifyEvent,
    key_press: ashet.abi.KeyboardEvent,
    key_release: ashet.abi.KeyboardEvent,
    mouse_enter: ashet.abi.MouseEvent,
    mouse_leave: ashet.abi.MouseEvent,
    mouse_motion: ashet.abi.MouseEvent,
    mouse_button_press: ashet.abi.MouseEvent,
    mouse_button_release: ashet.abi.MouseEvent,
    window_close,
    window_minimize,
    window_restore,
    window_moving,
    window_moved,
    window_resizing,
    window_resized,
};

const WindowList = std.DoublyLinkedList(void);
const WindowNode = WindowList.Node;

meta_pressed: bool = false,
mouse_action: MouseAction = .default,

min_window_content_size: ashet.abi.Size,
max_window_content_size: ashet.abi.Size,
maximized_window_rect: ashet.abi.Rectangle,

focused_window: ?*Window = null,

active_windows: WindowList = .{},

damage_tracking: *DamageTracking,

pub fn init(damage_tracking: *DamageTracking) WindowManager {
    const max_size = .{
        .width = damage_tracking.tracked_area.width - 2,
        .height = damage_tracking.tracked_area.height - 12,
    };
    return .{
        .damage_tracking = damage_tracking,

        .min_window_content_size = .{
            .width = 39,
            .height = 9,
        },
        .max_window_content_size = max_size,
        .maximized_window_rect = Rectangle.new(Point.new(1, 11), max_size),
    };
}

pub fn deinit(wm: *WindowManager) void {
    wm.* = undefined;
}

// Must be called after all pending events have been processed
pub fn handle_after_events(wm: *WindowManager) !void {
    const previous_focus = wm.focused_window;
    if (wm.update_focus()) {
        if (previous_focus != wm.focused_window) {
            if (previous_focus) |win| wm.damage_tracking.invalidate_region(win.screenRectangle());
            if (wm.focused_window) |win| wm.damage_tracking.invalidate_region(win.screenRectangle());
        }
    }
}

pub fn handle_event(wm: *WindowManager, mouse_point: Point, input_event: ashet.input.Event) !void {
    switch (input_event) {
        .key_press,
        .key_release,
        => |event| try wm.handle_keyboard_event(event),

        .mouse_abs_motion,
        .mouse_rel_motion,
        .mouse_button_press,
        .mouse_button_release,
        => |event| try wm.handle_mouse_event(mouse_point, event),
    }
}
fn handle_keyboard_event(wm: *WindowManager, event: ashet.abi.KeyboardEvent) !void {
    if (event.key == .meta) {
        // swallow all access to meta into the UI. Windows never see the meta key!
        wm.meta_pressed = event.pressed;
    } else if (wm.focused_window) |window| {
        if (!window.flags.minimized) {
            window.pushEvent(switch (event.event_type.input) {
                .key_press => .{ .key_press = event },
                .key_release => .{ .key_release = event },
                .mouse_abs_motion,
                .mouse_rel_motion,
                .mouse_button_press,
                .mouse_button_release,
                => unreachable,
            });
        }
    }
}

fn handle_mouse_event(wm: *WindowManager, mouse_point: Point, event: ashet.abi.MouseEvent) !void {
    // const mouse_point = Point.new(@as(i16, @intCast(event.x)), @as(i16, @intCast(event.y)));
    // if (event.type == .motion) {
    //     invalidateScreen();
    // }
    switch (wm.mouse_action) {
        .default => try wm.handle_default_mouse_event(mouse_point, event),
        .drag_window => |*action| try wm.handle_drag_window_mouse_event(mouse_point, event, action),
        .resize_window => |*action| try wm.handle_resize_window_mouse_event(mouse_point, event, action),
    }
}

fn handle_default_mouse_event(wm: *WindowManager, mouse_point: Point, event: ashet.abi.MouseEvent) !void {
    switch (event.event_type.input) {
        .key_press, .key_release => unreachable,
        .mouse_button_press => {
            if (wm.window_from_cursor(mouse_point)) |surface| {
                if (event.button == .left) {
                    // TODO: If was moved to top, send activate event
                    wm.move_window_to_top(surface.window);

                    if (wm.top_window()) |top_win| {
                        wm.damage_tracking.invalidate_region(top_win.screenRectangle());
                    }
                    wm.damage_tracking.invalidate_region(surface.window.screenRectangle());

                    if (wm.meta_pressed and !surface.window.is_maximized()) {
                        wm.mouse_action = MouseAction{
                            .drag_window = DragAction{
                                .window = surface.window,
                                .start = mouse_point,
                            },
                        };
                        return;
                    }

                    switch (surface.part) {
                        .title_bar => {
                            if (!surface.window.is_maximized()) {
                                wm.mouse_action = MouseAction{
                                    .drag_window = DragAction{
                                        .window = surface.window,
                                        .start = mouse_point,
                                    },
                                };
                            }
                            return;
                        },
                        .button => |button| switch (button) {
                            .minimize => wm.minimize_window(surface.window),
                            .maximize => wm.maximize_window(surface.window),
                            .restore => wm.restore_window(surface.window),
                            .close => {
                                surface.window.pushEvent(.window_close);
                                return;
                            },
                            .resize => {
                                wm.mouse_action = MouseAction{
                                    .resize_window = DragAction{
                                        .window = surface.window,
                                        .start = mouse_point,
                                    },
                                };
                                return;
                            },
                        },
                        .content => {}, // ignore event here, just forward
                    }
                }

                if (surface.part == .content) {
                    // TODO(fqu): Re-enable mouse events: surface.window.pushEvent(.{ .mouse = surface.window.makeMouseRelative(event) });
                }
            } else if (wm.minimized_from_cursor(mouse_point)) |mini| {
                if (event.button == .left) {
                    if (mini.restore_button.contains(mouse_point)) {
                        wm.restore_window(mini.window);
                        wm.move_window_to_top(mini.window);
                        wm.damage_tracking.invalidate_region(mini.window.screenRectangle());
                        var list = wm.minimized_iterator();
                        while (list.next()) |minmin| {
                            wm.damage_tracking.invalidate_region(minmin.bounds);
                        }
                    } else if (mini.close_button.contains(mouse_point)) {
                        mini.window.pushEvent(.window_close);
                    } else {
                        wm.damage_tracking.invalidate_region(mini.bounds);
                        wm.focused_window = mini.window;
                    }
                }
            } else {
                // user clicked desktop, handle desktop icons here
                logger.warn("desktop clicked at {}.", .{mouse_point});
                // TODO(fqu): desktop.sendClick(mouse_point);
            }
        },
        .mouse_button_release,
        .mouse_abs_motion,
        .mouse_rel_motion,
        => {
            if (wm.window_from_cursor(mouse_point)) |surface| {
                if (surface.part == .content) {
                    // TODO(fqu): Forward mouse events: surface.window.pushEvent(.{ .mouse = surface.window.makeMouseRelative(event) });
                }
            }
        },
    }
}

fn handle_drag_window_mouse_event(wm: *WindowManager, mouse_point: Point, event: ashet.abi.MouseEvent, action: *DragAction) !void {
    defer action.start = mouse_point;
    const dx = @as(i15, @intCast(mouse_point.x - action.start.x));
    const dy = @as(i15, @intCast(mouse_point.y - action.start.y));

    if (event.button == .left and event.event_type.input == .mouse_button_release) {
        action.window.pushEvent(.window_moved);
        wm.mouse_action = .default; // must be last, we override the contents of action with this!
        return;
    }

    if (dx != 0 or dy != 0) {
        wm.damage_tracking.invalidate_region(action.window.screenRectangle());
        logger.info("move window {}, {}", .{ dx, dy });
        action.window.client_rectangle.x += dx;
        action.window.client_rectangle.y += dy;
        action.window.pushEvent(.window_moving);
        wm.damage_tracking.invalidate_region(action.window.screenRectangle());
    }
}

fn handle_resize_window_mouse_event(wm: *WindowManager, mouse_point: Point, event: ashet.abi.MouseEvent, action: *DragAction) !void {
    defer action.start = mouse_point;
    const dx = @as(i15, @intCast(mouse_point.x - action.start.x));
    const dy = @as(i15, @intCast(mouse_point.y - action.start.y));

    if (event.button == .left and event.event_type.input == .mouse_button_release) {
        action.window.pushEvent(.window_resized);
        wm.mouse_action = .default; // must be last, we override the contents of action with this!
        return;
    }

    if (dx != 0 or dy != 0) {
        const rect = &action.window.client_rectangle;
        const min = action.window.min_size;
        const max = action.window.max_size;

        const prev_screen_rect = action.window.screenRectangle();
        const previous = rect.size();

        rect.width = @intCast(std.math.clamp(@as(i17, rect.width) + dx, min.width, max.width));
        rect.height = @intCast(std.math.clamp(@as(i17, rect.height) + dy, min.height, max.height));

        if (!rect.size().eql(previous)) {
            wm.damage_tracking.invalidate_region(prev_screen_rect);
            wm.damage_tracking.invalidate_region(action.window.screenRectangle());
            action.window.pushEvent(.window_resizing);
        }
    }
}

const WindowSurface = struct {
    const Part = union(enum) {
        title_bar,
        button: ButtonEvent,
        content,
    };

    window: *Window,
    part: Part,

    fn init(window: *Window, part: Part) WindowSurface {
        return WindowSurface{ .window = window, .part = part };
    }
};

fn window_from_cursor(wm: *WindowManager, point: Point) ?WindowSurface {
    var iter = wm.window_iterator(WindowIterator.is_regular, .top_to_bottom);
    while (iter.next()) |window| {
        const client_rectangle = window.client_rectangle;
        const window_rectangle = window.screenRectangle();

        if (window_rectangle.contains(point)) {
            var buttons = window.get_buttons();
            for (buttons.slice()) |btn| {
                if (btn.bounds.contains(point)) {
                    return WindowSurface.init(window, .{ .button = btn.event });
                }
            }

            if (client_rectangle.contains(point)) {
                // we can only be over the window content if we didn't hit a button.
                // this is intended
                return WindowSurface.init(window, .content);
            }

            return WindowSurface.init(window, .title_bar);
        }
    }
    return null;
}

pub fn render(wm: *WindowManager, q: *ashet.graphics.CommandQueue, theme: themes.Theme) !void {
    {
        var iter = wm.minimized_iterator();
        while (iter.next()) |mini| {
            const window = mini.window;

            if (!wm.damage_tracking.is_area_tainted(mini.bounds))
                continue;

            const style = if (window.flags.focus)
                theme.active_window
            else
                theme.inactive_window;

            const dx = mini.bounds.x;
            const dy = mini.bounds.y;
            const width = @as(u15, @intCast(mini.bounds.width));

            try q.draw_horizontal_line(Point.new(dx, dy), width, style.border);
            try q.draw_horizontal_line(Point.new(dx, dy + 10), width, style.border);
            try q.draw_vertical_line(Point.new(dx, dy + 1), 9, style.border);
            try q.draw_vertical_line(Point.new(dx + width - 1, dy + 1), 9, style.border);
            try q.fill_rect(Rectangle{ .x = dx + 1, .y = dy + 1, .width = width - 2, .height = 9 }, style.title);

            try q.draw_text(Point.new(dx + 2, dy + 2), theme.title_font, style.font, mini.title); //  width - 2);

            try paintButton(q, mini.restore_button, style, style.title, icons.restore_from_tray);
            try paintButton(q, mini.close_button, style, style.title, icons.close);
        }
    }
    {
        var iter = wm.window_iterator(WindowIterator.is_regular, .bottom_to_top);
        while (iter.next()) |window| {
            const client_rectangle = window.client_rectangle;
            const window_rectangle = window.screenRectangle();

            const style = if (window.flags.focus)
                theme.active_window
            else
                theme.inactive_window;

            const buttons = window.get_buttons();

            const title_width = @as(u15, @intCast(window_rectangle.width - 2));

            try q.draw_horizontal_line(Point.new(window_rectangle.x, window_rectangle.y), window_rectangle.width, style.border);
            try q.draw_vertical_line(Point.new(window_rectangle.x, window_rectangle.y + 1), window_rectangle.height - 1, style.border);

            try q.draw_horizontal_line(Point.new(window_rectangle.x, window_rectangle.y + @as(i16, @intCast(window_rectangle.height)) - 1), window_rectangle.width, style.border);
            try q.draw_vertical_line(Point.new(window_rectangle.x + @as(i16, @intCast(window_rectangle.width)) - 1, window_rectangle.y + 1), window_rectangle.height - 1, style.border);

            try q.draw_horizontal_line(Point.new(window_rectangle.x + 1, window_rectangle.y + 10), window_rectangle.width - 2, style.border);

            try q.fill_rect(Rectangle{ .x = window_rectangle.x + 1, .y = window_rectangle.y + 1, .width = title_width, .height = 9 }, style.title);

            try q.draw_text(
                Point.new(
                    window_rectangle.x + 2,
                    window_rectangle.y + 2,
                ),
                theme.title_font,
                style.font,
                window.title(),
                // TODO(fqu): title_width - 2,
            );

            try q.blit_partial_framebuffer(
                client_rectangle,
                Point.zero,
                window.framebuffer,
            );

            for (buttons.slice()) |button| {
                const bounds = button.bounds;
                const bg = if (button.bounds.y == window_rectangle.y)
                    style.title
                else
                    theme.dark;
                switch (button.event) {
                    inline else => |tag| try paintButton(q, bounds, style, bg, @field(icons, @tagName(tag))),
                }
            }
        }
    }
}

pub fn create_window(
    wm: *WindowManager,
    window_handle: ashet.abi.Window,
) !void {
    const framebuffer = try ashet.graphics.create_window_framebuffer(window_handle);
    errdefer framebuffer.release();

    const window: *Window = Window.from_handle(window_handle);

    // TODO: Fetch initial info block

    // const caption: []const u8 = "Example Window";
    const min: ashet.abi.Size = Size.new(100, 100);
    const max: ashet.abi.Size = Size.new(300, 200);
    const initial_size: Size = Size.new(200, 150);
    const flags: ashet.abi.CreateWindowFlags = .{
        .popup = false,
    };

    window.* = Window{
        .manager = wm,
        .handle = window_handle,
        .framebuffer = framebuffer,
        .client_rectangle = undefined,
        .min_size = wm.limit_window_size(size_min(min, max)),
        .max_size = wm.limit_window_size(size_max(min, max)),
        .flags = .{
            .minimized = false,
            .focus = false,
            .popup = flags.popup,
        },
    };

    const clamped_initial_size = size_max(size_min(initial_size, window.max_size), window.min_size);

    window.client_rectangle = Rectangle{
        .x = 16,
        .y = 16,
        .width = clamped_initial_size.width,
        .height = clamped_initial_size.height,
    };
    logger.info("initial: {}", .{window.client_rectangle});

    if (wm.top_window()) |top_win| blk: {
        const spawn_x = top_win.client_rectangle.x + 16;
        const spawn_y = top_win.client_rectangle.y + 16;

        if (spawn_x + @as(i17, top_win.client_rectangle.width) >= wm.damage_tracking.tracked_area.width)
            break :blk;
        if (spawn_y + @as(i17, top_win.client_rectangle.height) >= wm.damage_tracking.tracked_area.height)
            break :blk;

        window.client_rectangle.x = spawn_x;
        window.client_rectangle.y = spawn_y;
    }

    // TODO: try window.setTitle(caption);

    wm.active_windows.append(&window.node);

    wm.move_window_to_top(window);

    wm.damage_tracking.invalidate_screen();
}

pub fn destroy_window(wm: *WindowManager, window_handle: ashet.abi.Window) void {
    const window: *Window = Window.from_handle(window_handle);

    wm.active_windows.remove(&window.node);
    if (wm.focused_window == window) {
        wm.focused_window = null;
    }

    wm.damage_tracking.invalidate_region(window.screenRectangle());

    switch (wm.mouse_action) {
        .default => {},
        .drag_window => |act| if (act.window == window) {
            wm.mouse_action = .default;
        },
        .resize_window => |act| if (act.window == window) {
            wm.mouse_action = .default;
        },
    }

    window.framebuffer.release();
}

pub fn restore_window(wm: *WindowManager, window: *Window) void {

    // first, invalidate all regions
    var list = wm.minimized_iterator();
    while (list.next()) |minmin| {
        wm.damage_tracking.invalidate_region(minmin.bounds);
    }

    window.client_rectangle = window.saved_restore_location;

    // then maximize the window. The invalidation will ensure
    // the now maximized window will be undrawn
    window.flags.minimized = false;
    window.pushEvent(.window_restore);
}

pub fn minimize_window(wm: *WindowManager, window: *Window) void {
    if (!window.can_minimize())
        return;

    if (!window.flags.minimized) {
        window.saved_restore_location = window.client_rectangle;
    }

    window.flags.minimized = true;
    window.pushEvent(.window_minimize);

    var list = wm.minimized_iterator();
    while (list.next()) |minmin| {
        wm.damage_tracking.invalidate_region(minmin.bounds);
    }
}

pub fn maximize_window(wm: *WindowManager, window: *Window) void {
    if (!window.can_maximize())
        return;

    if (!window.is_maximized()) {
        window.saved_restore_location = window.client_rectangle;
    }

    window.client_rectangle = wm.maximized_window_rect;
    window.pushEvent(.window_moved);
    window.pushEvent(.window_resized);

    wm.damage_tracking.invalidate_screen();
}

/// Windows can be resized if their minimum size and maximum size differ
pub fn is_window_resizable(wm: *WindowManager, window: *const Window) bool {
    _ = wm;
    return (window.min_size.width != window.max_size.width) or
        (window.min_size.height != window.max_size.height);
}

pub fn is_window_maximized(wm: *WindowManager, window: *const Window) bool {
    return std.meta.eql(window.client_rectangle, wm.maximized_window_rect);
}

/// Windows can be maximized if their maximum size is the full screen size
pub fn can_window_maximize(wm: *WindowManager, window: *const Window) bool {
    return (window.max_size.width == wm.max_window_content_size.width) and
        (window.max_size.height == wm.max_window_content_size.height);
}

/// All windows except popups can be minimized.
pub fn can_window_minimize(wm: *WindowManager, window: *const Window) bool {
    _ = wm;
    return !window.flags.popup;
}

const ButtonEvent = enum { minimize, maximize, restore, close, resize };

const WindowButton = struct {
    event: ButtonEvent,
    bounds: Rectangle,
};

const DragAction = struct { window: *Window, start: Point };
const MouseAction = union(enum) {
    default,
    drag_window: DragAction,
    resize_window: DragAction,
};

pub const Window = struct {
    node: WindowList.Node = .{ .data = {} },

    handle: ashet.abi.Window,

    manager: *WindowManager,

    framebuffer: ashet.graphics.Framebuffer,

    /// The current position of the window on the screen. Will not contain the decorators, but only
    /// the position of the framebuffer.
    client_rectangle: Rectangle,

    /// The minimum size of this window. The window can never be smaller than this.
    min_size: Size,

    /// The maximum size of this window. The window can never be bigger than this.
    max_size: Size,

    /// A collection of informative flags.
    flags: Flags,

    saved_restore_location: Rectangle = undefined,

    pub fn from_handle(window_handle: ashet.abi.Window) *Window {
        return @ptrCast(@alignCast(
            ashet.gui.get_desktop_data(window_handle) catch @panic("kernel bug"),
        ));
    }

    pub fn screenRectangle(window: Window) Rectangle {
        const rect = window.client_rectangle;
        return Rectangle{
            .x = rect.x -| 1,
            .y = rect.y -| 11,
            .width = rect.width +| 2,
            .height = rect.height +| 12,
        };
    }

    pub fn title(window: Window) [:0]const u8 {
        _ = window;
        return "untitled";
    }

    // pub fn setTitle(window: *Window, text: []const u8) !void {
    //     try window.title_buffer.resize(text.len + 1);
    //     std.mem.copyForwards(u8, window.title_buffer.items, text);
    //     window.title_buffer.items[text.len] = 0;
    //     window.title = window.title().ptr;
    // }

    pub fn pushEvent(window: *Window, event: WindowEvent) void {
        var raw_event: ashet.abi.WindowEvent = switch (event) {
            .widget_notify => |data| .{ .widget_notify = data },
            .key_press => |data| .{ .keyboard = data },
            .key_release => |data| .{ .keyboard = data },
            .mouse_enter => |data| .{ .mouse = data },
            .mouse_leave => |data| .{ .mouse = data },
            .mouse_motion => |data| .{ .mouse = data },
            .mouse_button_press => |data| .{ .mouse = data },
            .mouse_button_release => |data| .{ .mouse = data },
            .window_close => .{ .event_type = .window_close },
            .window_minimize => .{ .event_type = .window_minimize },
            .window_restore => .{ .event_type = .window_restore },
            .window_moving => .{ .event_type = .window_moving },
            .window_moved => .{ .event_type = .window_moved },
            .window_resizing => .{ .event_type = .window_resizing },
            .window_resized => .{ .event_type = .window_resized },
        };
        raw_event.event_type = event;

        // logger.info("push {} for {s}", .{ event, window.title() });
        ashet.gui.post_window_event(window.handle, raw_event) catch |err| {
            logger.err("failed to post window event: {s}", .{@errorName(err)});
        };
    }

    pub fn makeMouseRelative(window: *Window, event: ashet.abi.MouseEvent) ashet.abi.MouseEvent {
        var rel_event = event;
        rel_event.x = rel_event.x - window.client_rectangle.x;
        rel_event.y = rel_event.y - window.client_rectangle.y;
        return rel_event;
    }

    const ButtonCollection = std.BoundedArray(WindowButton, std.enums.values(ButtonEvent).len);

    pub fn get_buttons(window: *const Window) ButtonCollection {
        const rectangle = window.screenRectangle();
        var buttons = ButtonCollection{};

        var top_row = Rectangle{
            .x = rectangle.x +| @as(u15, @intCast(rectangle.width)) -| 11,
            .y = rectangle.y,
            .width = 11,
            .height = 11,
        };

        buttons.appendAssumeCapacity(WindowButton{ .bounds = top_row, .event = .close });

        if (window.manager.can_window_maximize(window)) {
            top_row.x -= 10;
            if (window.manager.is_window_maximized(window)) {
                buttons.appendAssumeCapacity(WindowButton{ .bounds = top_row, .event = .restore });
            } else {
                buttons.appendAssumeCapacity(WindowButton{ .bounds = top_row, .event = .maximize });
            }
        }
        if (window.manager.can_window_minimize(window)) {
            top_row.x -= 10;
            buttons.appendAssumeCapacity(WindowButton{ .bounds = top_row, .event = .minimize });
        }

        if (window.manager.is_window_resizable(window) and !window.is_maximized()) {
            buttons.appendAssumeCapacity(WindowButton{
                .bounds = Rectangle{
                    .x = rectangle.x + @as(u15, @intCast(rectangle.width)) - 11,
                    .y = rectangle.y + @as(u15, @intCast(rectangle.height)) - 11,
                    .width = 11,
                    .height = 11,
                },
                .event = .resize,
            });
        }

        return buttons;
    }

    pub fn is_maximized(window: *const Window) bool {
        return window.manager.is_window_maximized(window);
    }

    pub fn can_maximize(window: *const Window) bool {
        return window.manager.can_window_maximize(window);
    }

    pub fn can_minimize(window: *const Window) bool {
        return window.manager.can_window_minimize(window);
    }

    pub const Flags = packed struct(u8) {
        /// The window is currently minimized.
        minimized: bool,

        /// The window currently has keyboard focus.
        focus: bool,

        /// This window is a popup and cannot be minimized
        popup: bool,

        padding: u5 = 0,
    };
};

fn size_min(a: Size, b: Size) Size {
    return .{
        .width = @min(a.width, b.width),
        .height = @min(a.height, b.height),
    };
}

fn size_max(a: Size, b: Size) Size {
    return .{
        .width = @max(a.width, b.width),
        .height = @max(a.height, b.height),
    };
}

fn node_to_window(node: *WindowList.Node) *Window {
    return @fieldParentPtr("node", node);
}

fn limit_window_size(wm: WindowManager, size: Size) Size {
    logger.info("limit_window_size({}, {}, {})", .{ size, wm.min_window_content_size, wm.max_window_content_size });
    return Size{
        .width = std.math.clamp(size.width, wm.min_window_content_size.width, wm.max_window_content_size.width),
        .height = std.math.clamp(size.height, wm.min_window_content_size.height, wm.max_window_content_size.height),
    };
}

const MinimizedWindow = struct {
    window: *Window,
    bounds: Rectangle,
    close_button: Rectangle,
    restore_button: Rectangle,
    title: []const u8,
};

fn minimized_iterator(wm: *WindowManager) MinimizedIterator {
    return MinimizedIterator{
        .dx = 4,
        .dy = @as(i16, @intCast(wm.damage_tracking.tracked_area.height - 11 - 4)),
        .inner = wm.window_iterator(WindowIterator.is_minimized, .bottom_to_top),
    };
}

const MinimizedIterator = struct {
    dx: i16,
    dy: i16,
    inner: WindowIterator,

    fn next(iter: *MinimizedIterator) ?MinimizedWindow {
        const window = iter.inner.next() orelse return null;

        const title = window.title();
        const width = @as(u15, @intCast(@min(6 * title.len + 2 + 11 + 10, 75)));
        defer iter.dx += (width + 4);

        const mini = MinimizedWindow{
            .window = window,
            .bounds = Rectangle{
                .x = iter.dx,
                .y = iter.dy,
                .width = width,
                .height = 11,
            },
            .close_button = Rectangle{
                .x = iter.dx + width - 11,
                .y = iter.dy,
                .width = 11,
                .height = 11,
            },
            .restore_button = Rectangle{
                .x = iter.dx + width - 21,
                .y = iter.dy,
                .width = 11,
                .height = 11,
            },
            .title = title,
        };

        return mini;
    }
};

fn minimized_from_cursor(wm: *WindowManager, pt: Point) ?MinimizedWindow {
    var iter = wm.minimized_iterator();
    while (iter.next()) |mini| {
        if (mini.bounds.contains(pt)) {
            return mini;
        }
    }
    return null;
}

fn paintButton(q: *ashet.graphics.CommandQueue, bounds: Rectangle, style: themes.WindowStyle, bg: ColorIndex, icon: *const ashet.graphics.Bitmap) !void {
    try q.draw_horizontal_line(Point.new(bounds.x, bounds.y), bounds.width, style.border);
    try q.draw_horizontal_line(Point.new(bounds.x, bounds.y + @as(u15, @intCast(bounds.width)) - 1), bounds.width, style.border);
    try q.draw_vertical_line(Point.new(bounds.x, bounds.y), bounds.height, style.border);
    try q.draw_vertical_line(Point.new(bounds.x + @as(u15, @intCast(bounds.width)) - 1, bounds.y), bounds.height, style.border);
    try q.fill_rect(bounds.shrink(1), bg);
    try q.blit_bitmap(Point.new(bounds.x + 1, bounds.y + 1), icon);
}

fn window_iterator(wm: *WindowManager, filter: WindowIterator.Filter, direction: WindowIterator.Direction) WindowIterator {
    return WindowIterator{
        .it = switch (direction) {
            .bottom_to_top => wm.active_windows.first,
            .top_to_bottom => wm.active_windows.last,
        },
        .filter = filter,
        .direction = direction,
    };
}

/// will move the window to the top, and unminimizes it.
fn move_window_to_top(wm: *WindowManager, window: *Window) void {
    window.flags.minimized = false;
    wm.active_windows.remove(&window.node);
    wm.active_windows.append(&window.node);
    wm.focused_window = window;
}

fn top_window(wm: *WindowManager) ?*Window {
    var iter = wm.window_iterator(WindowIterator.is_regular, .top_to_bottom);
    return iter.next();
}

/// Updates which windows has the focus bit set.
fn update_focus(wm: *WindowManager) bool {
    var changes = false;
    var iter = wm.window_iterator(WindowIterator.all, .top_to_bottom);
    while (iter.next()) |win| {
        const has_focus = (wm.focused_window == win);
        if (win.flags.focus != has_focus) {
            changes = true;
        }
        win.flags.focus = has_focus;
    }
    return true;
}

const WindowIterator = struct {
    const Filter = *const fn (*Window) bool;
    const Direction = enum { top_to_bottom, bottom_to_top };

    it: ?*WindowList.Node,
    filter: Filter,
    direction: Direction,

    /// Lists all windows
    pub fn all(_: *Window) bool {
        return true;
    }

    /// Lists all minimized windows
    pub fn is_minimized(w: *Window) bool {
        return w.flags.minimized;
    }

    /// Lists all non-minimized windows
    pub fn is_regular(w: *Window) bool {
        return !w.flags.minimized;
    }

    fn next(self: *WindowIterator) ?*Window {
        while (true) {
            const node = self.it orelse return null;
            self.it = switch (self.direction) {
                .bottom_to_top => node.next,
                .top_to_bottom => node.prev,
            };
            const window = node_to_window(node);
            if (self.filter(window))
                return window;
        }
    }
};
