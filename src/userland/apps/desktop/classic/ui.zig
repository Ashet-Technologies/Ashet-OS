const std = @import("std");
const astd = @import("ashet-std");
const gui = @import("ashet-gui");
const logger = std.log.scoped(.ui);
const ashet = @import("../main.zig");
const system_assets = @import("system-assets");
const libashet = @import("ashet");

const Size = ashet.abi.Size;
const Point = ashet.abi.Point;
const Rectangle = ashet.abi.Rectangle;
const ColorIndex = ashet.abi.ColorIndex;
const Color = ashet.abi.Color;
const Bitmap = gui.Bitmap;
const Framebuffer = gui.Framebuffer;

const ButtonEvent = enum { minimize, maximize, restore, close, resize };
const WindowButton = struct {
    event: ButtonEvent,
    bounds: Rectangle,
};

pub const Theme = struct {
    pub const WindowStyle = struct {
        border: ColorIndex,
        font: ColorIndex,
        title: ColorIndex,
    };
    active_window: WindowStyle,
    inactive_window: WindowStyle,
    dark: ColorIndex,
    desktop_color: ColorIndex,
    window_fill: ColorIndex,
};

var current_theme = Theme{
    .dark = ashet.video.defaults.known_colors.dark_gray,
    .active_window = Theme.WindowStyle{
        .border = ashet.video.defaults.known_colors.dark_blue,
        .font = ashet.video.defaults.known_colors.white,
        .title = ashet.video.defaults.known_colors.blue,
    },
    .inactive_window = Theme.WindowStyle{
        .border = ashet.video.defaults.known_colors.dim_gray,
        .font = ashet.video.defaults.known_colors.bright_gray,
        .title = ashet.video.defaults.known_colors.dark_gray,
    },
    .desktop_color = ashet.video.defaults.known_colors.teal,
    .window_fill = ashet.video.defaults.known_colors.gray,
};

var framebuffer: gui.Framebuffer = undefined;

var min_window_content_size: ashet.abi.Size = undefined;

var max_window_content_size: ashet.abi.Size = undefined;

var maximized_window_rect: ashet.abi.Rectangle = undefined;

const DragAction = struct { window: *Window, start: Point };
const MouseAction = union(enum) {
    default,
    drag_window: DragAction,
    resize_window: DragAction,
};

var mouse_action: MouseAction = .default;

pub fn getSystemFont(font_name: []const u8) error{FileNotFound}![]const u8 {
    return try system_fonts.get(font_name);
}

fn run(_: ?*anyopaque) callconv(.C) u32 {
    system_fonts.load() catch |err| {
        logger.err("failed to initialize system fonts: {s}", .{@errorName(err)});
        return 1;
    };

    gui.init() catch |err| {
        logger.err("failed to initialize gui: {s}", .{@errorName(err)});
        return 1;
    };

    desktop.init();

    // demo.init();

    while (true) {
        while (ashet.multi_tasking.exclusive_video_controller != null) {
            // wait until no process has access to the screen
            ashet.scheduler.yield();
        }

        // set up the gpu after a process might have changed
        // everything about the graphics state.
        initializeGraphics();

        // Reset the state
        mouse_action = .default;

        // Mark the right window focused
        _ = WindowIterator.updateFocus();

        // Enforce a full repaint of the user interface, so we have it "online"
        invalidateScreen();
        repaint();

        var meta_pressed = false;

        while (ashet.multi_tasking.exclusive_video_controller == null) {
            const prev_cursor_pos = ashet.input.cursor;

            event_loop: while (ashet.input.getEvent()) |input_event| {
                switch (input_event) {
                    .keyboard => |event| {
                        if (event.key == .meta) {
                            // swallow all access to meta into the UI. Windows never see the meta key!
                            meta_pressed = event.pressed;
                        } else if (focused_window) |window| {
                            if (!window.user_facing.flags.minimized) {
                                window.pushEvent(.{ .keyboard = event });
                            }
                        }
                    },
                    .mouse => |event| {
                        const mouse_point = Point.new(@as(i16, @intCast(event.x)), @as(i16, @intCast(event.y)));
                        // if (event.type == .motion) {
                        //     invalidateScreen();
                        // }
                        switch (mouse_action) {
                            .default => {
                                switch (event.type) {
                                    .button_press => {
                                        if (windowFromCursor(mouse_point)) |surface| {
                                            if (event.button == .left) {
                                                // TODO: If was moved to top, send activate event
                                                WindowIterator.moveToTop(surface.window);

                                                if (WindowIterator.topWindow()) |top_win| {
                                                    invalidateRegion(top_win.screenRectangle());
                                                }
                                                invalidateRegion(surface.window.screenRectangle());

                                                if (meta_pressed and !surface.window.isMaximized()) {
                                                    mouse_action = MouseAction{
                                                        .drag_window = DragAction{
                                                            .window = surface.window,
                                                            .start = mouse_point,
                                                        },
                                                    };
                                                    continue :event_loop;
                                                }

                                                switch (surface.part) {
                                                    .title_bar => {
                                                        if (!surface.window.isMaximized()) {
                                                            mouse_action = MouseAction{
                                                                .drag_window = DragAction{
                                                                    .window = surface.window,
                                                                    .start = mouse_point,
                                                                },
                                                            };
                                                        }
                                                        continue :event_loop;
                                                    },
                                                    .button => |button| switch (button) {
                                                        .minimize => surface.window.minimize(),
                                                        .maximize => surface.window.maximize(),
                                                        .restore => surface.window.restore(),
                                                        .close => {
                                                            surface.window.pushEvent(.window_close);
                                                            continue :event_loop;
                                                        },
                                                        .resize => {
                                                            mouse_action = MouseAction{
                                                                .resize_window = DragAction{
                                                                    .window = surface.window,
                                                                    .start = mouse_point,
                                                                },
                                                            };
                                                            continue :event_loop;
                                                        },
                                                    },
                                                    .content => {}, // ignore event here, just forward
                                                }
                                            }

                                            if (surface.part == .content) {
                                                surface.window.pushEvent(.{ .mouse = surface.window.makeMouseRelative(event) });
                                            }
                                        } else if (minimizedFromCursor(mouse_point)) |mini| {
                                            if (event.button == .left) {
                                                if (mini.restore_button.contains(mouse_point)) {
                                                    mini.window.restore();
                                                    WindowIterator.moveToTop(mini.window);
                                                    invalidateRegion(mini.window.screenRectangle());
                                                    var list = MinimizedIterator.init();
                                                    while (list.next()) |minmin| {
                                                        invalidateRegion(minmin.bounds);
                                                    }
                                                } else if (mini.close_button.contains(mouse_point)) {
                                                    mini.window.pushEvent(.window_close);
                                                } else {
                                                    invalidateRegion(mini.bounds);
                                                    focused_window = mini.window;
                                                }
                                            }
                                        } else {
                                            // user clicked desktop, handle desktop icons here
                                            desktop.sendClick(mouse_point);
                                        }
                                    },
                                    .button_release, .motion => {
                                        if (windowFromCursor(mouse_point)) |surface| {
                                            if (surface.part == .content) {
                                                surface.window.pushEvent(.{ .mouse = surface.window.makeMouseRelative(event) });
                                            }
                                        }
                                    },
                                }
                            },
                            .drag_window => |*action| blk: {
                                defer action.start = mouse_point;
                                const dx = @as(i15, @intCast(mouse_point.x - action.start.x));
                                const dy = @as(i15, @intCast(mouse_point.y - action.start.y));

                                if (event.button == .left and event.type == .button_release) {
                                    action.window.pushEvent(.window_moved);
                                    mouse_action = .default; // must be last, we override the contents of action with this!
                                    break :blk;
                                } else if (dx != 0 or dy != 0) {
                                    invalidateRegion(action.window.screenRectangle());
                                    action.window.user_facing.client_rectangle.x += dx;
                                    action.window.user_facing.client_rectangle.y += dy;
                                    action.window.pushEvent(.window_moving);
                                    invalidateRegion(action.window.screenRectangle());
                                }
                            },
                            .resize_window => |*action| blk: {
                                defer action.start = mouse_point;
                                const dx = @as(i15, @intCast(mouse_point.x - action.start.x));
                                const dy = @as(i15, @intCast(mouse_point.y - action.start.y));

                                if (event.button == .left and event.type == .button_release) {
                                    action.window.pushEvent(.window_resized);
                                    mouse_action = .default; // must be last, we override the contents of action with this!
                                    break :blk;
                                } else if (dx != 0 or dy != 0) {
                                    const rect = &action.window.user_facing.client_rectangle;
                                    const min = action.window.user_facing.min_size;
                                    const max = action.window.user_facing.max_size;

                                    const prev_screen_rect = action.window.screenRectangle();
                                    const previous = rect.size();

                                    rect.width = @intCast(std.math.clamp(@as(i17, rect.width) + dx, min.width, max.width));
                                    rect.height = @intCast(std.math.clamp(@as(i17, rect.height) + dy, min.height, max.height));

                                    if (!rect.size().eql(previous)) {
                                        invalidateRegion(prev_screen_rect);
                                        invalidateRegion(action.window.screenRectangle());
                                        action.window.pushEvent(.window_resizing);
                                    }
                                }
                            },
                        }
                    },
                }
            }

            const mouse_moved = !prev_cursor_pos.eql(ashet.input.cursor);

            if (mouse_moved) {
                invalidateRegion(Rectangle{
                    .x = prev_cursor_pos.x,
                    .y = prev_cursor_pos.y,
                    .width = icons.cursor.width,
                    .height = icons.cursor.height,
                });
                invalidateRegion(Rectangle{
                    .x = ashet.input.cursor.x,
                    .y = ashet.input.cursor.y,
                    .width = icons.cursor.width,
                    .height = icons.cursor.height,
                });
            }

            const previous_focus = focused_window;
            if (WindowIterator.updateFocus()) {
                if (previous_focus != focused_window) {
                    if (previous_focus) |win| invalidateRegion(win.screenRectangle());
                    if (focused_window) |win| invalidateRegion(win.screenRectangle());
                }
            }

            if (invalidation_areas.len > 0) {
                logger.debug("repaint", .{});
                repaint();
            }

            ashet.scheduler.yield();
        }
    }
}

var invalidation_areas = std.BoundedArray(Rectangle, 8){};

fn framebufferBounds() Rectangle {
    return Rectangle.new(Point.zero, framebuffer.size());
}

pub fn invalidateScreen() void {
    invalidateRegion(framebufferBounds());
}

pub fn invalidateRegion(region: Rectangle) void {
    if (region.empty())
        return;

    // check if we already have this region invalidated
    for (invalidation_areas.slice()) |rect| {
        if (rect.containsRectangle(region))
            return;
    }

    logger.debug("invalidate {}", .{region});

    if (invalidation_areas.len == invalidation_areas.capacity()) {
        invalidation_areas.len = 1;
        invalidation_areas.buffer[0] = framebufferBounds();
        return;
    }

    invalidation_areas.appendAssumeCapacity(region);
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

fn windowFromCursor(point: Point) ?WindowSurface {
    var iter = WindowIterator.init(WindowIterator.regular, .top_to_bottom);
    while (iter.next()) |window| {
        const client_rectangle = window.user_facing.client_rectangle;
        const window_rectangle = window.screenRectangle();

        if (window_rectangle.contains(point)) {
            var buttons = window.getButtons();
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

// offsets for well-known palette items
const framebuffer_wallpaper_shift = 255 - 15;
const framebuffer_default_icon_shift = 0; // framebuffer_wallpaper_shift - 15;

fn initializeGraphics() void {
    const max_res = ashet.video.getMaxResolution();
    ashet.video.setBorder(ColorIndex.get(0));
    ashet.video.setResolution(@as(u15, @truncate(max_res.width)), @as(u15, @truncate(max_res.height)));
    const resolution = ashet.video.getResolution();

    framebuffer = gui.Framebuffer{
        .width = @as(u15, @intCast(resolution.width)),
        .height = @as(u15, @intCast(resolution.height)),
        .stride = @as(u15, @intCast(resolution.width)),
        .pixels = ashet.video.getVideoMemory().ptr,
    };

    min_window_content_size = .{
        .width = 39,
        .height = 9,
    };
    max_window_content_size = .{
        .width = framebuffer.width - 2,
        .height = framebuffer.height - 12,
    };
    maximized_window_rect = Rectangle.new(Point.new(1, 11), max_window_content_size);

    const palette = ashet.video.getPaletteMemory();
    palette.* = ashet.video.defaults.palette;

    // for (desktop.apps.slice()) |app| {
    //     std.mem.copyForwards(Color, palette[app.palette_base .. app.palette_base + 15], &app.icon.palette);
    // }

    // std.mem.copyForwards(Color, palette[framebuffer_default_icon_shift..], &desktop.default_icon.palette);
    std.mem.copyForwards(Color, palette[framebuffer_wallpaper_shift..], &wallpaper.palette);
}

const MinimizedWindow = struct {
    window: *Window,
    bounds: Rectangle,
    close_button: Rectangle,
    restore_button: Rectangle,
    title: []const u8,
};

const MinimizedIterator = struct {
    dx: i16,
    dy: i16,
    inner: WindowIterator,

    fn init() MinimizedIterator {
        return MinimizedIterator{
            .dx = 4,
            .dy = @as(i16, @intCast(framebuffer.height - 11 - 4)),
            .inner = WindowIterator.init(WindowIterator.minimized, .bottom_to_top),
        };
    }

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

fn minimizedFromCursor(pt: Point) ?MinimizedWindow {
    var iter = MinimizedIterator.init();
    while (iter.next()) |mini| {
        if (mini.bounds.contains(pt)) {
            return mini;
        }
    }
    return null;
}

fn paintButton(bounds: Rectangle, style: Theme.WindowStyle, bg: ColorIndex, icon: Bitmap) void {
    framebuffer.horizontalLine(bounds.x, bounds.y, bounds.width, style.border);
    framebuffer.horizontalLine(bounds.x, bounds.y + @as(u15, @intCast(bounds.width)) - 1, bounds.width, style.border);
    framebuffer.verticalLine(bounds.x, bounds.y, bounds.height, style.border);
    framebuffer.verticalLine(bounds.x + @as(u15, @intCast(bounds.width)) - 1, bounds.y, bounds.height, style.border);
    framebuffer.fillRectangle(bounds.shrink(1), bg);
    framebuffer.blit(Point.new(bounds.x + 1, bounds.y + 1), icon);
}

fn isTainted(rect: Rectangle) bool {
    for (invalidation_areas.slice()) |r| {
        if (r.intersects(rect))
            return true;
    }
    return false;
}

fn repaint() void {
    defer invalidation_areas.len = 0; // we've redrawn the whole screen, no need for painting at all

    // Copy the wallpaper to the framebuffer
    // for (wallpaper.pixels) |c, i| {
    //     framebuffer.fb[i] = c.shift(framebuffer_wallpaper_shift - 1);
    // }

    // framebuffer.blit(Point.zero, wallpaper.bitmap);

    // framebuffer.clear(ColorIndex.get(7));

    const title_font = gui.Font.fromSystemFont("mono-8", .{}) catch gui.Font.default;

    for (invalidation_areas.slice()) |rect| {
        framebuffer.fillRectangle(rect, current_theme.desktop_color);
    }

    desktop.paint();

    {
        var iter = MinimizedIterator.init();
        while (iter.next()) |mini| {
            const window = mini.window;

            if (!isTainted(mini.bounds))
                continue;

            const style = if (window.user_facing.flags.focus)
                current_theme.active_window
            else
                current_theme.inactive_window;

            const dx = mini.bounds.x;
            const dy = mini.bounds.y;
            const width = @as(u15, @intCast(mini.bounds.width));

            framebuffer.horizontalLine(dx, dy, width, style.border);
            framebuffer.horizontalLine(dx, dy + 10, width, style.border);
            framebuffer.verticalLine(dx, dy + 1, 9, style.border);
            framebuffer.verticalLine(dx + width - 1, dy + 1, 9, style.border);
            framebuffer.fillRectangle(Rectangle{ .x = dx + 1, .y = dy + 1, .width = width - 2, .height = 9 }, style.title);

            framebuffer.drawString(dx + 2, dy + 2, mini.title, &title_font, style.font, width - 2);

            paintButton(mini.restore_button, style, style.title, icons.restore_from_tray);
            paintButton(mini.close_button, style, style.title, icons.close);
        }
    }
    {
        var iter = WindowIterator.init(WindowIterator.regular, .bottom_to_top);
        while (iter.next()) |window| {
            const client_rectangle = window.user_facing.client_rectangle;
            const window_rectangle = window.screenRectangle();

            const style = if (window.user_facing.flags.focus)
                current_theme.active_window
            else
                current_theme.inactive_window;

            const buttons = window.getButtons();

            const title_width = @as(u15, @intCast(window_rectangle.width - 2));

            framebuffer.horizontalLine(window_rectangle.x, window_rectangle.y, window_rectangle.width, style.border);
            framebuffer.verticalLine(window_rectangle.x, window_rectangle.y + 1, window_rectangle.height - 1, style.border);

            framebuffer.horizontalLine(window_rectangle.x, window_rectangle.y + @as(i16, @intCast(window_rectangle.height)) - 1, window_rectangle.width, style.border);
            framebuffer.verticalLine(window_rectangle.x + @as(i16, @intCast(window_rectangle.width)) - 1, window_rectangle.y + 1, window_rectangle.height - 1, style.border);

            framebuffer.horizontalLine(window_rectangle.x + 1, window_rectangle.y + 10, window_rectangle.width - 2, style.border);

            framebuffer.fillRectangle(Rectangle{ .x = window_rectangle.x + 1, .y = window_rectangle.y + 1, .width = title_width, .height = 9 }, style.title);

            framebuffer.drawString(
                window_rectangle.x + 2,
                window_rectangle.y + 2,
                window.title(),
                &title_font,
                style.font,
                title_width - 2,
            );

            var dy: u15 = 0;
            var row_ptr = window.user_facing.pixels;
            while (dy < client_rectangle.height) : (dy += 1) {
                var dx: u15 = 0;
                while (dx < client_rectangle.width) : (dx += 1) {
                    framebuffer.setPixel(client_rectangle.x + dx, client_rectangle.y + dy, row_ptr[dx]);
                }
                row_ptr += window.user_facing.stride;
            }

            for (buttons.slice()) |button| {
                const bounds = button.bounds;
                const bg = if (button.bounds.y == window_rectangle.y)
                    style.title
                else
                    current_theme.dark;
                switch (button.event) {
                    inline else => |tag| paintButton(bounds, style, bg, @field(icons, @tagName(tag))),
                }
            }
        }
    }

    framebuffer.blit(ashet.input.cursor, icons.cursor);
}

var focused_window: ?*Window = null;

const WindowIterator = struct {
    const Filter = *const fn (*Window) bool;
    const Direction = enum { top_to_bottom, bottom_to_top };

    var list = WindowQueue{};

    it: ?*WindowQueue.Node,
    filter: Filter,
    direction: Direction,

    pub fn topWindow() ?*Window {
        var iter = init(regular, .top_to_bottom);
        return iter.next();
    }

    /// will move the window to the top, and unminimizes it.
    pub fn moveToTop(window: *Window) void {
        window.user_facing.flags.minimized = false;
        list.remove(&window.node);
        list.append(&window.node);
        focused_window = window;
    }

    /// Updates which windows has the focus bit set.
    pub fn updateFocus() bool {
        var changes = false;
        var iter = init(all, .top_to_bottom);
        while (iter.next()) |win| {
            const has_focus = (focused_window == win);
            if (win.user_facing.flags.focus != has_focus) {
                changes = true;
            }
            win.user_facing.flags.focus = has_focus;
        }
        return true;
    }

    pub fn init(filter: Filter, direction: Direction) WindowIterator {
        return WindowIterator{
            .it = switch (direction) {
                .bottom_to_top => list.first,
                .top_to_bottom => list.last,
            },
            .filter = filter,
            .direction = direction,
        };
    }

    pub fn next(self: *WindowIterator) ?*Window {
        while (true) {
            const node = self.it orelse return null;
            self.it = switch (self.direction) {
                .bottom_to_top => node.next,
                .top_to_bottom => node.prev,
            };
            const window = nodeToWindow(node);
            if (self.filter(window))
                return window;
        }
    }

    /// Lists all windows
    pub fn all(_: *Window) bool {
        return true;
    }

    /// Lists all minimized windows
    pub fn minimized(w: *Window) bool {
        return w.user_facing.flags.minimized;
    }

    /// Lists all non-minimized windows
    pub fn regular(w: *Window) bool {
        return !w.user_facing.flags.minimized;
    }
};

const WindowQueue = std.DoublyLinkedList(void);

const Event = union(ashet.abi.UiEventType) {
    mouse: ashet.abi.MouseEvent,
    keyboard: ashet.abi.KeyboardEvent,
    window_close,
    window_minimize,
    window_restore,
    window_moving,
    window_moved,
    window_resizing,
    window_resized,
};

pub fn destroyAllWindowsForProcess(proc: *ashet.multi_tasking.Process) void {
    var iter = WindowIterator.init(WindowIterator.all, .top_to_bottom);
    while (iter.next()) |window| {
        if (window.owner == proc) {
            window.destroy();
        }
    }
}

fn eventToIOP(event: Event) ashet.abi.ui.GetEvent.Outputs {
    var iop = ashet.abi.ui.GetEvent.Outputs{
        .event_type = event,
        .event = undefined,
    };
    switch (event) {
        .mouse => |val| iop.event = .{ .mouse = val },
        .keyboard => |val| iop.event = .{ .keyboard = val },
        .window_close, .window_minimize, .window_restore, .window_moving, .window_moved, .window_resizing, .window_resized => {},
    }
    return iop;
}

pub fn getEvent(data: *ashet.abi.ui.GetEvent) void {
    const window: *Window = Window.getFromABI(data.inputs.window);
    if (window.event_awaiter != null)
        return ashet.io.finalizeWithError(data, error.InProgress);

    data.@"error" = .ok; // otherwise always ok, just might take time
    if (window.pullEvent()) |event| {
        ashet.io.finalizeWithResult(data, eventToIOP(event));
    } else {
        window.event_awaiter = data;
    }
}

pub fn cancelGetEvent(data: *ashet.abi.ui.GetEvent) void {
    const window: *Window = Window.getFromABI(data.inputs.window);
    if (window.event_awaiter == data) {
        window.event_awaiter = null;
    } else {
        logger.warn("IOP({*}) is not scheduled right now!", .{data});
    }
}

pub const Window = struct {
    memory: std.heap.ArenaAllocator,
    user_facing: ashet.abi.Window,
    title_buffer: std.ArrayList(u8),
    owner: ?*ashet.multi_tasking.Process,

    saved_restore_size: Rectangle = undefined,

    node: WindowQueue.Node = .{ .data = {} },
    event_queue: astd.RingBuffer(Event, 16) = .{}, // 16 events should be easily enough

    event_awaiter: ?*ashet.abi.ui.GetEvent = null,

    pub fn getFromABI(win: *const ashet.abi.Window) *Window {
        const window: *Window = @constCast(@alignCast(@fieldParentPtr("user_facing", win)));
        // return @as(*Window, @ptrFromInt(@intFromPtr(window)));
        return window;
    }

    pub fn create(
        owner: ?*ashet.multi_tasking.Process,
        caption: []const u8,
        min: ashet.abi.Size,
        max: ashet.abi.Size,
        initial_size: Size,
        flags: ashet.abi.CreateWindowFlags,
    ) !*Window {
        var temp_arena = std.heap.ArenaAllocator.init(ashet.memory.allocator);
        var window = temp_arena.allocator().create(Window) catch |err| {
            temp_arena.deinit();
            return err;
        };

        window.* = Window{
            .owner = owner,
            .memory = temp_arena,
            .user_facing = ashet.abi.Window{
                .pixels = undefined,
                .stride = max_window_content_size.width,
                .client_rectangle = undefined,
                .min_size = limitWindowSize(sizeMin(min, max)),
                .max_size = limitWindowSize(sizeMax(min, max)),
                .title = "",
                .flags = .{
                    .minimized = false,
                    .focus = false,
                    .popup = flags.popup,
                },
            },
            .title_buffer = undefined,
        };
        errdefer window.memory.deinit();

        const allocator = window.memory.allocator();

        window.title_buffer = std.ArrayList(u8).init(allocator);
        try window.title_buffer.ensureTotalCapacity(64);

        const pixel_count = @as(usize, window.user_facing.max_size.height) * @as(usize, window.user_facing.stride);
        window.user_facing.pixels = (try allocator.alloc(ColorIndex, pixel_count)).ptr;
        @memset(window.user_facing.pixels[0..pixel_count], current_theme.window_fill);

        const clamped_initial_size = sizeMax(sizeMin(initial_size, window.user_facing.max_size), window.user_facing.min_size);

        window.user_facing.client_rectangle = Rectangle{
            .x = 16,
            .y = 16,
            .width = clamped_initial_size.width,
            .height = clamped_initial_size.height,
        };

        if (WindowIterator.topWindow()) |top_window| blk: {
            const spawn_x = top_window.user_facing.client_rectangle.x + 16;
            const spawn_y = top_window.user_facing.client_rectangle.y + 16;

            if (spawn_x + @as(i17, top_window.user_facing.client_rectangle.width) >= framebuffer.width)
                break :blk;
            if (spawn_y + @as(i17, top_window.user_facing.client_rectangle.height) >= framebuffer.height)
                break :blk;

            window.user_facing.client_rectangle.x = spawn_x;
            window.user_facing.client_rectangle.y = spawn_y;
        }

        try window.setTitle(caption);

        WindowIterator.list.append(&window.node);

        WindowIterator.moveToTop(window);

        invalidateRegion(window.screenRectangle());

        return window;
    }

    pub fn destroy(window: *Window) void {
        WindowIterator.list.remove(&window.node);
        if (focused_window == window) {
            focused_window = null;
        }

        invalidateRegion(window.screenRectangle());

        switch (mouse_action) {
            .default => {},
            .drag_window => |act| if (act.window == window) {
                mouse_action = .default;
            },
            .resize_window => |act| if (act.window == window) {
                mouse_action = .default;
            },
        }

        var clone = window.memory;
        window.* = undefined;
        clone.deinit();
    }

    pub fn screenRectangle(window: Window) Rectangle {
        const rect = window.user_facing.client_rectangle;
        return Rectangle{
            .x = rect.x - 1,
            .y = rect.y - 11,
            .width = rect.width + 2,
            .height = rect.height + 12,
        };
    }

    pub fn title(window: Window) [:0]const u8 {
        const str = window.title_buffer.items;
        return str[0 .. str.len - 1 :0];
    }

    pub fn setTitle(window: *Window, text: []const u8) !void {
        try window.title_buffer.resize(text.len + 1);
        std.mem.copyForwards(u8, window.title_buffer.items, text);
        window.title_buffer.items[text.len] = 0;
        window.user_facing.title = window.title().ptr;
    }

    pub fn pushEvent(window: *Window, event: Event) void {
        // logger.info("push {} for {s}", .{ event, window.title() });

        if (window.event_awaiter) |awaiter| {
            ashet.io.finalizeWithResult(awaiter, eventToIOP(event));
            window.event_awaiter = null;
        } else {
            window.event_queue.push(event);
        }
    }

    pub fn pullEvent(window: *Window) ?Event {
        return window.event_queue.pull();
    }

    pub fn makeMouseRelative(window: *Window, event: ashet.abi.MouseEvent) ashet.abi.MouseEvent {
        var rel_event = event;
        rel_event.x = rel_event.x - window.user_facing.client_rectangle.x;
        rel_event.y = rel_event.y - window.user_facing.client_rectangle.y;
        return rel_event;
    }

    pub fn restore(window: *Window) void {

        // first, invalidate all regions
        var list = MinimizedIterator.init();
        while (list.next()) |minmin| {
            invalidateRegion(minmin.bounds);
        }

        window.user_facing.client_rectangle = window.saved_restore_size;

        // then maximize the window. The invalidation will ensure
        // the now maximized window will be undrawn
        window.user_facing.flags.minimized = false;
        window.pushEvent(.window_restore);
    }

    pub fn minimize(window: *Window) void {
        if (!window.canMinimize())
            return;

        if (!window.user_facing.flags.minimized) {
            window.saved_restore_size = window.user_facing.client_rectangle;
        }

        window.user_facing.flags.minimized = true;
        window.pushEvent(.window_minimize);

        var list = MinimizedIterator.init();
        while (list.next()) |minmin| {
            invalidateRegion(minmin.bounds);
        }
    }

    pub fn maximize(window: *Window) void {
        if (!window.canMaximize())
            return;

        if (!window.isMaximized()) {
            window.saved_restore_size = window.user_facing.client_rectangle;
        }

        window.user_facing.client_rectangle = maximized_window_rect;
        window.pushEvent(.window_moved);
        window.pushEvent(.window_resized);

        invalidateScreen();
    }

    /// Windows can be resized if their minimum size and maximum size differ
    pub fn isResizable(window: Window) bool {
        return (window.user_facing.min_size.width != window.user_facing.max_size.width) or
            (window.user_facing.min_size.height != window.user_facing.max_size.height);
    }

    pub fn isMaximized(window: Window) bool {
        return std.meta.eql(window.user_facing.client_rectangle, maximized_window_rect);
    }

    /// Windows can be maximized if their maximum size is the full screen size
    pub fn canMaximize(window: Window) bool {
        return (window.user_facing.max_size.width == max_window_content_size.width) and
            (window.user_facing.max_size.height == max_window_content_size.height);
    }

    /// All windows except popups can be minimized.
    pub fn canMinimize(window: Window) bool {
        return !window.user_facing.flags.popup;
    }

    const ButtonCollection = std.BoundedArray(WindowButton, std.enums.values(ButtonEvent).len);
    pub fn getButtons(window: Window) ButtonCollection {
        const rectangle = window.screenRectangle();
        var buttons = ButtonCollection{};

        var top_row = Rectangle{
            .x = rectangle.x + @as(u15, @intCast(rectangle.width)) - 11,
            .y = rectangle.y,
            .width = 11,
            .height = 11,
        };

        buttons.appendAssumeCapacity(WindowButton{ .bounds = top_row, .event = .close });

        if (window.canMaximize()) {
            top_row.x -= 10;
            if (window.isMaximized()) {
                buttons.appendAssumeCapacity(WindowButton{ .bounds = top_row, .event = .restore });
            } else {
                buttons.appendAssumeCapacity(WindowButton{ .bounds = top_row, .event = .maximize });
            }
        }
        if (window.canMinimize()) {
            top_row.x -= 10;
            buttons.appendAssumeCapacity(WindowButton{ .bounds = top_row, .event = .minimize });
        }

        if (window.isResizable() and !window.isMaximized()) {
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
};

fn limitWindowSize(size: Size) Size {
    return Size{
        .width = std.math.clamp(size.width, min_window_content_size.width, max_window_content_size.width),
        .height = std.math.clamp(size.height, min_window_content_size.height, max_window_content_size.height),
    };
}

fn sizeMin(a: Size, b: Size) Size {
    return Size{
        .width = @min(a.width, b.width),
        .height = @min(a.height, b.height),
    };
}

fn sizeMax(a: Size, b: Size) Size {
    return Size{
        .width = @max(a.width, b.width),
        .height = @max(a.height, b.height),
    };
}

fn nodeToWindow(node: *WindowQueue.Node) *Window {
    return @fieldParentPtr("node", node);
}

const wallpaper = struct {
    const raw = @embedFile("../data/ui/wallpaper.img");

    const pixels = blk: {
        @setEvalBranchQuota(4 * 400 * 300);

        const data = @as([400 * 300]ColorIndex, @bitCast(raw[0 .. 400 * 300].*));

        for (data) |*c| {
            c.* = c.shift(framebuffer_wallpaper_shift - 1);
        }

        break :blk data;
    };
    const palette = @as([15]Color, @bitCast(@as([]const u8, raw)[400 * 300 .. 400 * 300 + 15 * @sizeOf(Color)].*));

    const bitmap = Bitmap{
        .width = 400,
        .height = 300,
        .stride = 400,
        .pixels = &pixels,
        .transparent = null,
    };
};
