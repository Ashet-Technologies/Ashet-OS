const std = @import("std");
const astd = @import("ashet-std");
const logger = std.log.scoped(.ui);
const ashet = @import("../main.zig");

pub fn start() !void {
    const T = struct {
        var started = false;
    };
    if (T.started)
        return error.AlreadyStarted;
    T.started = true;

    const thread = try ashet.scheduler.Thread.spawn(run, null, .{
        .stack_size = 2 * 65536,
    });
    try thread.setName("ui.run");
    try thread.start();
    thread.detach();
}

const Size = ashet.abi.Size;
const Point = ashet.abi.Point;
const Rectangle = ashet.abi.Rectangle;
const ColorIndex = ashet.abi.ColorIndex;
const Color = ashet.abi.Color;

const ButtonEvent = enum { minimize, maximize, close, resize };
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
};

var current_theme = Theme{
    .dark = ColorIndex.get(0x3), // dark gray
    .active_window = Theme.WindowStyle{
        .border = ColorIndex.get(0x2), // dark blue
        .font = ColorIndex.get(0xF), // white
        .title = ColorIndex.get(0x8), // bright blue
    },
    .inactive_window = Theme.WindowStyle{
        .border = ColorIndex.get(0x1), // dark violet
        .font = ColorIndex.get(0xA), // bright gray
        .title = ColorIndex.get(0x3), // dim gray
    },
};

const min_window_content_size = ashet.abi.Size{
    .width = 39,
    .height = 9,
};

const max_window_content_size = ashet.abi.Size{
    .width = framebuffer.width - 2,
    .height = framebuffer.height - 12,
};

var mouse_cursor_pos: Point = .{
    .x = framebuffer.width / 2,
    .y = framebuffer.height / 2,
};

const DragAction = struct { window: *Window, start: Point };
const MouseAction = union(enum) {
    default,
    drag_window: DragAction,
    resize_window: DragAction,
};

var mouse_action: MouseAction = .default;

// const demo = struct {
//     var windows = std.BoundedArray(*Window, 5){};

//     fn init() void {
//         const bot = Window.create(null, "Dragon Craft - src/main.zig", Size.new(0, 0), Size.new(200, 100), Size.new(200, 100)) catch @panic("oom");
//         const mid = Window.create(null, "Middle", Size.new(0, 0), Size.new(400, 300), Size.new(160, 80)) catch @panic("oom");
//         const top = Window.create(null, "Top", Size.new(47, 47), Size.new(47, 47), Size.new(47, 47)) catch @panic("oom");
//         top.user_facing.flags.focus = true;

//         windows.appendAssumeCapacity(bot);
//         windows.appendAssumeCapacity(mid);
//         windows.appendAssumeCapacity(top);
//     }

//     fn update() void {
//         var index: usize = 0;
//         loop: while (index < windows.len) {
//             const window = windows.buffer[index];

//             while (window.pullEvent()) |event| {
//                 logger.info("event for '{s}': {}", .{ window.title(), event });
//                 if (event == .window_close) {
//                     _ = windows.swapRemove(index);
//                     window.destroy();
//                     continue :loop;
//                 }
//             }
//             index += 1;
//         }
//     }
// };

fn run(_: ?*anyopaque) callconv(.C) u32 {
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
        repaint();

        var meta_pressed = false;

        while (ashet.multi_tasking.exclusive_video_controller == null) {
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
                        const mouse_point = Point.new(@intCast(i16, event.x), @intCast(i16, event.y));
                        mouse_cursor_pos.x = std.math.clamp(@intCast(i16, event.x), 0, framebuffer.width - 1);
                        mouse_cursor_pos.y = std.math.clamp(@intCast(i16, event.y), 0, framebuffer.height - 1);
                        if (event.type == .motion) {
                            invalidateScreen();
                        }
                        switch (mouse_action) {
                            .default => {
                                switch (event.type) {
                                    .button_press => {
                                        if (windowFromCursor(mouse_point)) |surface| {
                                            if (event.button == .left) {
                                                // TODO: If was moved to top, send activate event
                                                WindowIterator.moveToTop(surface.window);
                                                invalidateScreen();

                                                if (meta_pressed) {
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
                                                        mouse_action = MouseAction{
                                                            .drag_window = DragAction{
                                                                .window = surface.window,
                                                                .start = mouse_point,
                                                            },
                                                        };
                                                        continue :event_loop;
                                                    },
                                                    .button => |button| switch (button) {
                                                        .minimize => surface.window.minimize(),
                                                        .maximize => surface.window.maximize(),
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
                                                surface.window.pushEvent(.{ .mouse = event });
                                            }
                                        } else if (minimizedFromCursor(mouse_point)) |mini| {
                                            if (event.button == .left) {
                                                invalidateScreen();
                                                if (mini.restore_button.contains(mouse_point)) {
                                                    mini.window.restore();
                                                    WindowIterator.moveToTop(mini.window);
                                                } else if (mini.close_button.contains(mouse_point)) {
                                                    mini.window.pushEvent(.window_close);
                                                } else {
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
                                                surface.window.pushEvent(.{ .mouse = event });
                                            }
                                        }
                                    },
                                }
                            },
                            .drag_window => |*action| blk: {
                                defer action.start = mouse_point;
                                const dx = @intCast(i15, mouse_point.x - action.start.x);
                                const dy = @intCast(i15, mouse_point.y - action.start.y);

                                if (event.button == .left and event.type == .button_release) {
                                    action.window.pushEvent(.window_moved);
                                    mouse_action = .default; // must be last, we override the contents of action with this!
                                    break :blk;
                                } else if (dx != 0 or dy != 0) {
                                    action.window.user_facing.client_rectangle.x += dx;
                                    action.window.user_facing.client_rectangle.y += dy;
                                    action.window.pushEvent(.window_moving);
                                }
                            },
                            .resize_window => |*action| blk: {
                                defer action.start = mouse_point;
                                const dx = @intCast(i15, mouse_point.x - action.start.x);
                                const dy = @intCast(i15, mouse_point.y - action.start.y);

                                if (event.button == .left and event.type == .button_release) {
                                    action.window.pushEvent(.window_resized);
                                    mouse_action = .default; // must be last, we override the contents of action with this!
                                    break :blk;
                                } else if (dx != 0 or dy != 0) {
                                    const rect = &action.window.user_facing.client_rectangle;
                                    const min = action.window.user_facing.min_size;
                                    const max = action.window.user_facing.max_size;

                                    const previous = rect.size();

                                    rect.width = @intCast(u16, std.math.clamp(@as(i17, rect.width) + dx, min.width, max.width));
                                    rect.height = @intCast(u16, std.math.clamp(@as(i17, rect.height) + dy, min.height, max.height));

                                    if (!rect.size().eql(previous)) {
                                        action.window.pushEvent(.window_resizing);
                                    }
                                }
                            },
                        }
                    },
                }
            }

            if (WindowIterator.updateFocus()) {
                invalidateScreen();
            }

            if (invalidation_areas.len > 0) {
                invalidation_areas.len = 0;
                repaint();
            }

            // demo.update();

            ashet.scheduler.yield();
        }
    }
}

var invalidation_areas = std.BoundedArray(Rectangle, 8){};

pub fn invalidateScreen() void {
    invalidateRegion(framebuffer.bounds);
}

pub fn invalidateRegion(region: Rectangle) void {
    if (region.empty())
        return;

    // check if we already have this region invalidated
    for (invalidation_areas.slice()) |rect| {
        if (rect.containsRectangle(region))
            return;
    }
    if (invalidation_areas.len == invalidation_areas.capacity()) {
        invalidation_areas.len = 1;
        invalidation_areas.buffer[0] = framebuffer.bounds;
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
        const window_rectangle = expandClientRectangle(client_rectangle);

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
const framebuffer_default_icon_shift = framebuffer_wallpaper_shift - 15;

fn initializeGraphics() void {
    ashet.video.setBorder(ColorIndex.get(0));
    ashet.video.setResolution(framebuffer.width, framebuffer.height);

    ashet.video.palette.* = ashet.video.defaults.palette;

    for (desktop.apps.slice()) |app| {
        std.mem.copy(Color, ashet.video.palette[app.palette_base .. app.palette_base + 15], &app.icon.palette);
    }

    std.mem.copy(Color, ashet.video.palette[framebuffer_default_icon_shift..], &desktop.default_icon.palette);
    std.mem.copy(Color, ashet.video.palette[framebuffer_wallpaper_shift..], &wallpaper.palette);
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
            .dy = framebuffer.height - 11 - 4,
            .inner = WindowIterator.init(WindowIterator.minimized, .bottom_to_top),
        };
    }

    fn next(iter: *MinimizedIterator) ?MinimizedWindow {
        const window = iter.inner.next() orelse return null;

        const title = window.title();
        const width = @intCast(u15, std.math.min(6 * title.len + 2 + 11 + 10, 75));
        defer iter.dx += (width + 4);

        var mini = MinimizedWindow{
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

fn paintButton(bounds: Rectangle, style: Theme.WindowStyle, bg: ColorIndex, icon: anytype) void {
    framebuffer.horizontalLine(bounds.x, bounds.y, bounds.width, style.border);
    framebuffer.horizontalLine(bounds.x, bounds.y + @intCast(u15, bounds.width) - 1, bounds.width, style.border);
    framebuffer.verticalLine(bounds.x, bounds.y, bounds.height, style.border);
    framebuffer.verticalLine(bounds.x + @intCast(u15, bounds.width) - 1, bounds.y, bounds.height, style.border);
    framebuffer.rectangle(bounds.x + 1, bounds.y + 1, bounds.width - 2, bounds.height - 2, bg);
    framebuffer.icon(bounds.x + 1, bounds.y + 1, &icon);
}

fn repaint() void {
    invalidation_areas.len = 0; // we've redrawn the whole screen, no need for painting at all

    // Copy the wallpaper to the framebuffer
    for (wallpaper.pixels) |c, i| {
        framebuffer.fb[i] = c.shift(framebuffer_wallpaper_shift - 1);
    }

    desktop.paint();

    {
        var iter = MinimizedIterator.init();
        while (iter.next()) |mini| {
            const window = mini.window;

            const style = if (window.user_facing.flags.focus)
                current_theme.active_window
            else
                current_theme.inactive_window;

            const dx = mini.bounds.x;
            const dy = mini.bounds.y;
            const width = @intCast(u15, mini.bounds.width);

            framebuffer.horizontalLine(dx, dy, width, style.border);
            framebuffer.horizontalLine(dx, dy + 10, width, style.border);
            framebuffer.verticalLine(dx, dy + 1, 9, style.border);
            framebuffer.verticalLine(dx + width - 1, dy + 1, 9, style.border);
            framebuffer.rectangle(dx + 1, dy + 1, width - 2, 9, style.title);

            framebuffer.text(dx + 2, dy + 2, mini.title, width - 2, style.font);

            paintButton(mini.restore_button, style, style.title, icons.restore);
            paintButton(mini.close_button, style, style.title, icons.close);
        }
    }
    {
        var iter = WindowIterator.init(WindowIterator.regular, .bottom_to_top);
        while (iter.next()) |window| {
            const client_rectangle = window.user_facing.client_rectangle;
            const window_rectangle = expandClientRectangle(client_rectangle);

            const style = if (window.user_facing.flags.focus)
                current_theme.active_window
            else
                current_theme.inactive_window;

            const buttons = window.getButtons();

            const title_width = @intCast(u15, window_rectangle.width - 2);

            framebuffer.horizontalLine(window_rectangle.x, window_rectangle.y, window_rectangle.width, style.border);
            framebuffer.verticalLine(window_rectangle.x, window_rectangle.y + 1, window_rectangle.height - 1, style.border);

            framebuffer.horizontalLine(window_rectangle.x, window_rectangle.y + @intCast(i16, window_rectangle.height) - 1, window_rectangle.width, style.border);
            framebuffer.verticalLine(window_rectangle.x + @intCast(i16, window_rectangle.width) - 1, window_rectangle.y + 1, window_rectangle.height - 1, style.border);

            framebuffer.horizontalLine(window_rectangle.x + 1, window_rectangle.y + 10, window_rectangle.width - 2, style.border);

            framebuffer.rectangle(window_rectangle.x + 1, window_rectangle.y + 1, title_width, 9, style.title);

            framebuffer.text(
                window_rectangle.x + 2,
                window_rectangle.y + 2,
                window.title(),
                title_width - 2,
                style.font,
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

    framebuffer.icon(mouse_cursor_pos.x, mouse_cursor_pos.y, &icons.cursor);
}

var focused_window: ?*Window = null;

const WindowIterator = struct {
    const Filter = std.meta.FnPtr(fn (*Window) bool);
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

const WindowQueue = std.TailQueue(void);

const Event = union(ashet.abi.UiEventType) {
    none,
    mouse: ashet.abi.MouseEvent,
    keyboard: ashet.abi.KeyboardEvent,
    window_close,
    window_minimize,
    window_restore,
    window_moving,
    window_moved,
    window_resized,
    window_resizing,
};

pub fn destroyAllWindowsForProcess(proc: *ashet.multi_tasking.Process) void {
    var iter = WindowIterator.init(WindowIterator.all, .top_to_bottom);
    while (iter.next()) |window| {
        if (window.owner == proc) {
            window.destroy();
        }
    }
}

pub const Window = struct {
    memory: std.heap.ArenaAllocator,
    user_facing: ashet.abi.Window,
    title_buffer: std.ArrayList(u8),
    owner: ?*ashet.multi_tasking.Process,

    node: WindowQueue.Node = .{ .data = {} },
    event_queue: astd.RingBuffer(Event, 16) = .{}, // 16 events should be easily enough

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
        std.mem.set(ColorIndex, window.user_facing.pixels[0..pixel_count], ColorIndex.get(4)); // brown

        const clamped_initial_size = sizeMax(sizeMin(initial_size, window.user_facing.max_size), window.user_facing.min_size);

        window.user_facing.client_rectangle = Rectangle{
            .x = 16,
            .y = 16,
            .width = clamped_initial_size.width,
            .height = clamped_initial_size.height,
        };

        if (WindowIterator.topWindow()) |top_window| blk: {
            var spawn_x = top_window.user_facing.client_rectangle.x + 16;
            var spawn_y = top_window.user_facing.client_rectangle.y + 16;

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

        return window;
    }

    pub fn destroy(window: *Window) void {
        WindowIterator.list.remove(&window.node);
        if (focused_window == window) {
            focused_window = null;
        }

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

    pub fn title(window: Window) [:0]const u8 {
        const str = window.title_buffer.items;
        return str[0 .. str.len - 1 :0];
    }

    pub fn setTitle(window: *Window, text: []const u8) !void {
        try window.title_buffer.resize(text.len + 1);
        std.mem.copy(u8, window.title_buffer.items, text);
        window.title_buffer.items[text.len] = 0;
        window.user_facing.title = window.title().ptr;
    }

    pub fn pushEvent(window: *Window, event: Event) void {
        // logger.info("push {} for {s}", .{ event, window.title() });
        window.event_queue.push(event);
    }

    pub fn pullEvent(window: *Window) ?Event {
        return window.event_queue.pull();
    }

    pub fn restore(window: *Window) void {
        window.user_facing.flags.minimized = false;
        window.pushEvent(.window_restore);
    }

    pub fn minimize(window: *Window) void {
        if (!window.canMinimize())
            return;
        window.user_facing.flags.minimized = true;
        window.pushEvent(.window_minimize);
    }

    pub fn maximize(window: *Window) void {
        if (!window.canMaximize())
            return;
        window.user_facing.client_rectangle = Rectangle.new(Point.new(1, 11), max_window_content_size);
        window.pushEvent(.window_moved);
        window.pushEvent(.window_resized);
    }

    /// Windows can be resized if their minimum size and maximum size differ
    pub fn isResizable(window: Window) bool {
        return (window.user_facing.min_size.width != window.user_facing.max_size.width) or
            (window.user_facing.min_size.height != window.user_facing.max_size.height);
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
        const rectangle = expandClientRectangle(window.user_facing.client_rectangle);
        var buttons = ButtonCollection{};

        var top_row = Rectangle{
            .x = rectangle.x + @intCast(u15, rectangle.width) - 11,
            .y = rectangle.y,
            .width = 11,
            .height = 11,
        };

        buttons.appendAssumeCapacity(WindowButton{ .bounds = top_row, .event = .close });

        if (window.canMaximize()) {
            top_row.x -= 10;
            buttons.appendAssumeCapacity(WindowButton{ .bounds = top_row, .event = .maximize });
        }
        if (window.canMinimize()) {
            top_row.x -= 10;
            buttons.appendAssumeCapacity(WindowButton{ .bounds = top_row, .event = .minimize });
        }

        if (window.isResizable()) {
            buttons.appendAssumeCapacity(WindowButton{
                .bounds = Rectangle{
                    .x = rectangle.x + @intCast(u15, rectangle.width) - 11,
                    .y = rectangle.y + @intCast(u15, rectangle.height) - 11,
                    .width = 11,
                    .height = 11,
                },
                .event = .resize,
            });
        }

        return buttons;
    }
};

fn expandClientRectangle(rect: Rectangle) Rectangle {
    return Rectangle{
        .x = rect.x - 1,
        .y = rect.y - 11,
        .width = rect.width + 2,
        .height = rect.height + 12,
    };
}

fn limitWindowSize(size: Size) Size {
    return Size{
        .width = std.math.clamp(size.width, min_window_content_size.width, max_window_content_size.width),
        .height = std.math.clamp(size.height, min_window_content_size.height, max_window_content_size.height),
    };
}

fn sizeMin(a: Size, b: Size) Size {
    return Size{
        .width = std.math.min(a.width, b.width),
        .height = std.math.min(a.height, b.height),
    };
}

fn sizeMax(a: Size, b: Size) Size {
    return Size{
        .width = std.math.max(a.width, b.width),
        .height = std.math.max(a.height, b.height),
    };
}

fn nodeToWindow(node: *WindowQueue.Node) *Window {
    return @fieldParentPtr(Window, "node", node);
}

const framebuffer = struct {
    const width = ashet.video.max_res_x;
    const height = ashet.video.max_res_y;
    const bounds = Rectangle{ .x = 0, .y = 0, .width = framebuffer.width, .height = framebuffer.height };

    const fb = ashet.video.memory[0 .. width * height];

    fn setPixel(x: i16, y: i16, color: ColorIndex) void {
        if (x < 0 or y < 0 or x >= width or y >= height) return;
        const ux = @intCast(usize, x);
        const uy = @intCast(usize, y);
        fb[uy * width + ux] = color;
    }

    fn horizontalLine(x: i16, y: i16, w: u16, color: ColorIndex) void {
        var i: u15 = 0;
        while (i < w) : (i += 1) {
            setPixel(x + i, y, color);
        }
    }

    fn verticalLine(x: i16, y: i16, h: u16, color: ColorIndex) void {
        var i: u15 = 0;
        while (i < h) : (i += 1) {
            setPixel(x, y + i, color);
        }
    }

    fn rectangle(x: i16, y: i16, w: u16, h: u16, color: ColorIndex) void {
        var i: i16 = y;
        while (i < y + @intCast(u15, h)) : (i += 1) {
            framebuffer.horizontalLine(x, i, w, color);
        }
    }

    fn icon(x: i16, y: i16, sprite: anytype) void {
        for (sprite) |row, dy| {
            for (row) |pix, dx| {
                const optpix: ?ColorIndex = pix; // allow both u8 and ?u8
                const color = optpix orelse continue;
                setPixel(x + @intCast(i16, dx), y + @intCast(i16, dy), color);
            }
        }
    }

    fn text(x: i16, y: i16, string: []const u8, max_width: u16, color: ColorIndex) void {
        const gw = 6;
        const gh = 8;
        const font = ashet.video.defaults.font;

        var dx: i16 = x;
        var dy: i16 = y;
        for (string) |char| {
            if (dx + gw > x + @intCast(u15, max_width)) {
                break;
            }
            const glyph = font[char];

            var gx: u15 = 0;
            while (gx < gw) : (gx += 1) {
                var bits = glyph[gx];

                comptime var gy: u15 = 0;
                inline while (gy < gh) : (gy += 1) {
                    if ((bits & (1 << gy)) != 0) {
                        setPixel(dx + gx, dy + gy, color);
                    }
                }
            }

            dx += gw;
        }
    }

    fn clear(color: ColorIndex) void {
        std.mem.set(ColorIndex, fb, color);
    }
};

pub const icons = struct {
    fn parsedSpriteSize(comptime def: []const u8) Size {
        var it = std.mem.split(u8, def, "\n");
        var first = it.next().?;
        const width = first.len;
        var height = 1;
        while (it.next()) |line| {
            std.debug.assert(line.len == width);
            height += 1;
        }
        return Size{ .width = width, .height = height };
    }

    fn ParseResult(comptime def: []const u8) type {
        const size = parsedSpriteSize(def);
        return [size.height][size.width]?ColorIndex;
    }

    fn parse(comptime def: []const u8) ParseResult(def) {
        @setEvalBranchQuota(10_000);

        const size = parsedSpriteSize(def);
        var icon: [size.height][size.width]?ColorIndex = [1][size.width]?ColorIndex{
            [1]?ColorIndex{null} ** size.width,
        } ** size.height;

        var it = std.mem.split(u8, def, "\n");
        var y: usize = 0;
        while (it.next()) |line| : (y += 1) {
            var x: usize = 0;
            while (x < icon[0].len) : (x += 1) {
                icon[y][x] = if (std.fmt.parseInt(u8, line[x .. x + 1], 16)) |index|
                    ColorIndex.get(index)
                else |_|
                    null;
            }
        }
        return icon;
    }

    pub const maximize = parse(
        \\.........
        \\.FFFFFFF.
        \\.F.....F.
        \\.FFFFFFF.
        \\.F.....F.
        \\.F.....F.
        \\.F.....F.
        \\.FFFFFFF.
        \\.........
    );

    pub const minimize = parse(
        \\.........
        \\.........
        \\.........
        \\.........
        \\.........
        \\.........
        \\.........
        \\..FFFFF..
        \\.........
    );

    pub const restore = parse(
        \\.........
        \\..FFFFF..
        \\.........
        \\.........
        \\.........
        \\.........
        \\.........
        \\.........
        \\.........
    );

    pub const close = parse(
        \\666666666
        \\666666666
        \\66F666F66
        \\666F6F666
        \\6666F6666
        \\666F6F666
        \\66F666F66
        \\666666666
        \\666666666
    );

    pub const resize = parse(
        \\.........
        \\.FFF.....
        \\.F.F.....
        \\.FFFFFFF.
        \\...F...F.
        \\...F...F.
        \\...F...F.
        \\...FFFFF.
        \\.........
    );

    pub const cursor = parse(
        \\888..........
        \\2FF88........
        \\2FFFF88......
        \\.2FFFFF88....
        \\.2FFFFFFF88..
        \\..2FFFFFFFF8.
        \\..2FFFFFFF8..
        \\...2FFFFF8...
        \\...2FFFFF8...
        \\....2FF22F8..
        \\....2F2..2F8.
        \\.....2....2F8
        \\...........2.
    );
};

const wallpaper = struct {
    const raw = @embedFile("../data/ui/wallpaper.img");

    const pixels = @bitCast([400 * 300]ColorIndex, raw[0 .. 400 * 300].*);
    const palette = @bitCast([15]Color, @as([]const u8, raw)[400 * 300 .. 400 * 300 + 15 * @sizeOf(Color)].*);
};

pub const desktop = struct {
    const Icon = struct {
        pub const width = 32;
        pub const height = 32;

        bitmap: [height][width]?ColorIndex,
        palette: [15]Color,

        pub fn load(stream: anytype, offset: u8) !Icon {
            var icon: Icon = undefined;

            var pixels: [height][width]u8 = undefined;

            try stream.readNoEof(std.mem.sliceAsBytes(&pixels));
            try stream.readNoEof(std.mem.sliceAsBytes(&icon.palette));

            for (pixels) |row, y| {
                for (row) |color, x| {
                    icon.bitmap[y][x] = if (color == 0)
                        null
                    else
                        ColorIndex.get(offset + color - 1);
                }
            }

            for (icon.bitmap) |row| {
                for (row) |c| {
                    std.debug.assert(c == null or (c.?.index() >= offset and c.?.index() < offset + 15));
                }
            }

            return icon;
        }
    };

    const default_icon = blk: {
        @setEvalBranchQuota(20_000);

        const data = @embedFile("../data/generic-app.icon");

        var stream = std.io.fixedBufferStream(data);

        break :blk Icon.load(stream.reader(), framebuffer_default_icon_shift) catch @compileError("invalid icon format");

        // var icon = Icon{ .bitmap = undefined, .palette = undefined };
        // std.mem.copy(u8, std.mem.sliceAsBytes(&icon.bitmap), data[0 .. 64 * 64]);
        // for (icon.palette) |*pal, i| {
        //     pal.* = @as(u16, pal_src[2 * i + 0]) << 0 |
        //         @as(u16, pal_src[2 * i + 1]) << 8;
        // }
        // break :blk icon;
    };

    const App = struct {
        name: [32]u8,
        icon: Icon,
        palette_base: u8,

        pub fn getName(app: *const App) []const u8 {
            return std.mem.sliceTo(&app.name, 0);
        }
    };

    const AppList = std.BoundedArray(App, 15);

    var apps: AppList = .{};
    var selected_app: ?usize = 0;
    var last_click: Point = undefined;

    const AppInfo = struct {
        app: *App,
        bounds: Rectangle,
        index: usize,
    };
    const AppIterator = struct {
        const lower_limit = framebuffer.height - 11 - 8 - 4;
        const padding = 8;

        index: usize = 0,
        bounds: Rectangle,

        pub fn init() AppIterator {
            return AppIterator{
                .bounds = Rectangle{
                    .x = 8,
                    .y = 8,
                    .width = Icon.width,
                    .height = Icon.height,
                },
            };
        }

        pub fn next(self: *AppIterator) ?AppInfo {
            if (self.index >= apps.len)
                return null;

            const info = AppInfo{
                .app = &apps.buffer[self.index],
                .index = self.index,
                .bounds = self.bounds,
            };
            self.index += 1;

            self.bounds.y += (Icon.height + padding);
            if (self.bounds.y >= lower_limit) {
                self.bounds.y = 8;
                self.bounds.x += (Icon.width + padding);
            }

            return info;
        }
    };

    fn init() void {
        reload() catch |err| {
            logger.err("failed to load desktop applications: {}", .{err});
        };
    }

    fn sendClick(point: Point) void {
        var iter = AppIterator.init();
        const selected = while (iter.next()) |info| {
            if (info.bounds.contains(point))
                break info.index;
        } else null;

        if (selected_app != selected) {
            last_click = point;
            invalidateScreen();
        } else if (selected_app) |app_index| {
            const app = &apps.buffer[app_index];
            if (last_click.manhattenDistance(point) < 2) {
                // logger.info("registered double click on app[{}]: {s}", .{ app_index, app.getName() });

                startApp(app.*) catch |err| logger.err("failed to start app {s}: {s}", .{ app.getName(), @errorName(err) });
            }
            last_click = point;
        }

        selected_app = selected;
    }

    fn startApp(app: App) !void {
        try ashet.apps.startApp(.{
            .name = app.getName(),
        });
    }

    fn paint() void {
        var iter = AppIterator.init();
        while (iter.next()) |info| {
            const app = info.app;

            const title = app.getName();

            if (selected_app == info.index) {
                framebuffer.icon(info.bounds.x - 1, info.bounds.y - 1, &dither_grid);
            }

            framebuffer.icon(info.bounds.x, info.bounds.y, &app.icon.bitmap);
            framebuffer.text(info.bounds.x + Icon.width / 2 - @intCast(u15, 3 * title.len), info.bounds.y + Icon.height, title, @intCast(u16, 6 * title.len), ColorIndex.get(0x0));
        }
    }

    fn reload() !void {
        var dir = try ashet.filesystem.openDir("SYS:/apps");
        defer ashet.filesystem.closeDir(dir);

        apps.len = 0;
        var pal_off: u8 = framebuffer_default_icon_shift;

        while (try ashet.filesystem.next(dir)) |ent| {
            const app = apps.addOne() catch {
                logger.warn("The system can only handle {} apps right now, but more are installed.", .{apps.len});
                break;
            };

            pal_off -= 15;
            app.* = App{
                .name = undefined,
                .icon = undefined,
                .palette_base = pal_off,
            };

            {
                const name = ent.getName();
                std.mem.set(u8, &app.name, 0);
                std.mem.copy(u8, &app.name, name[0..std.math.min(name.len, app.name.len)]);
            }

            var path_buffer: [ashet.abi.max_path]u8 = undefined;

            const icon_path = try std.fmt.bufPrint(&path_buffer, "SYS:/apps/{s}/icon", .{ent.getName()});

            if (ashet.filesystem.open(icon_path, .read_only, .open_existing)) |icon_handle| {
                defer ashet.filesystem.close(icon_handle);
                app.icon = try Icon.load(ashet.filesystem.fileReader(icon_handle), app.palette_base);
            } else |_| {
                std.log.warn("Application {s} does not have an icon. Using default.", .{ent.getName()});
                app.icon = default_icon;
            }
        }

        logger.info("loaded apps:", .{});
        for (apps.slice()) |app, index| {
            logger.info("app[{}]: {s}", .{ index, app.getName() });
        }
    }

    const dither_grid = blk: {
        @setEvalBranchQuota(2048);
        var buffer: [Icon.height + 2][Icon.width + 2]?ColorIndex = undefined;
        for (buffer) |*row, y| {
            for (row) |*c, x| {
                c.* = if ((y + x) % 2 == 0) ColorIndex.get(0) else null;
            }
        }
        break :blk buffer;
    };
};
