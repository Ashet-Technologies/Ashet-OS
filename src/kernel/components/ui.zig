const std = @import("std");
const ashet = @import("../main.zig");

const Size = ashet.abi.Size;
const Point = ashet.abi.Point;
const Rectangle = ashet.abi.Rectangle;
const ColorIndex = ashet.abi.ColorIndex;

pub const Theme = struct {
    pub const WindowStyle = struct {
        border: ColorIndex,
        font: ColorIndex,
        title: ColorIndex,
    };
    active_window: WindowStyle,
    inactive_window: WindowStyle,
};

var current_theme = Theme{
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

pub fn run(_: ?*anyopaque) callconv(.C) u32 {
    _ = createWindow("Bottom", Size.init(0, 0), Size.init(200, 100), Size.init(200, 100)) catch @panic("oom");
    _ = createWindow("Middle", Size.init(0, 0), Size.init(400, 300), Size.init(160, 80)) catch @panic("oom");
    const top = createWindow("Top", Size.init(47, 47), Size.init(47, 47), Size.init(47, 47)) catch @panic("oom");
    top.user_facing.flags.focus = true;

    while (true) {
        while (ashet.multi_tasking.exclusive_video_controller != null) {
            // wait until no process has access to the screen
            ashet.scheduler.yield();
        }

        // set up the gpu after a process might have changed
        // everything about the graphics state.
        initializeGraphics();

        // Enforce a full repaint of the user interface, so we have it "online"
        repaint();

        while (ashet.multi_tasking.exclusive_video_controller == null) {

            //

            ashet.scheduler.yield();
        }
    }
}

fn initializeGraphics() void {
    ashet.video.setBorder(ColorIndex.get(0));
    ashet.video.setResolution(framebuffer.width, framebuffer.height);
}

fn repaint() void {
    framebuffer.clear(ColorIndex.get(0));

    var iter = WindowIterator.init();
    while (iter.next()) |window| {
        const client_rectangle = window.user_facing.client_rectangle;
        const window_rectangle = expandClientRectangle(client_rectangle);

        const style = if (window.user_facing.flags.focus)
            current_theme.active_window
        else
            current_theme.inactive_window;

        const BoxType = enum { minimize, maximize, close };

        var boxes = std.BoundedArray(BoxType, 3){};
        {
            if (window.canMinimize()) {
                boxes.appendAssumeCapacity(.minimize);
            }
            if (window.canMaximize()) {
                boxes.appendAssumeCapacity(.maximize);
            }
            boxes.appendAssumeCapacity(.close);
        }

        const title_width = @intCast(u15, window_rectangle.width - 10 * boxes.len - 2);

        framebuffer.horizontalLine(window_rectangle.x, window_rectangle.y, window_rectangle.width, style.border);
        framebuffer.verticalLine(window_rectangle.x, window_rectangle.y + 1, window_rectangle.height - 1, style.border);

        framebuffer.horizontalLine(window_rectangle.x, window_rectangle.y + @intCast(i16, window_rectangle.height) - 1, window_rectangle.width, style.border);
        framebuffer.verticalLine(window_rectangle.x + @intCast(i16, window_rectangle.width) - 1, window_rectangle.y + 1, window_rectangle.height - 1, style.border);

        framebuffer.horizontalLine(window_rectangle.x + 1, window_rectangle.y + 10, window_rectangle.width - 2, style.border);

        framebuffer.rectangle(window_rectangle.x + 1, window_rectangle.y + 1, title_width, 9, style.title);

        framebuffer.text(
            window_rectangle.x + 2,
            window_rectangle.y + 2,
            std.mem.sliceTo(window.title.items, 0),
            title_width - 2,
            style.font,
        );

        {
            var x: i16 = window_rectangle.x + 1 + title_width;
            for (boxes.slice()) |box| {
                framebuffer.verticalLine(x, window_rectangle.y + 1, 9, style.border);
                framebuffer.rectangle(x + 1, window_rectangle.y + 1, 9, 9, style.title);
                switch (box) {
                    inline else => |tag| framebuffer.icon(x + 1, window_rectangle.y + 1, @field(icons, @tagName(tag))),
                }
                x += 10;
            }
        }

        var dy: u15 = 0;
        var row_ptr = window.user_facing.pixels;
        while (dy < client_rectangle.height) : (dy += 1) {
            var dx: u15 = 0;
            while (dx < client_rectangle.width) : (dx += 1) {
                framebuffer.setPixel(client_rectangle.x + dx, client_rectangle.y + dy, ColorIndex.get(row_ptr[dx]));
            }
            row_ptr += window.user_facing.stride;
        }
    }
}

var windows = WindowQueue{};

const WindowIterator = struct {
    it: ?*WindowQueue.Node,

    pub fn init() WindowIterator {
        return WindowIterator{
            .it = windows.first,
        };
    }

    pub fn next(self: *WindowIterator) ?*Window {
        const node = self.it orelse return null;
        self.it = node.next;
        return nodeToWindow(node);
    }
};

const WindowQueue = std.TailQueue(void);

const Window = struct {
    memory: std.heap.ArenaAllocator,
    user_facing: ashet.abi.Window,
    node: WindowQueue.Node,
    title: std.ArrayList(u8),

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
};

fn createWindow(title: []const u8, min: ashet.abi.Size, max: ashet.abi.Size, initial_size: Size) !*Window {
    var temp_arena = std.heap.ArenaAllocator.init(ashet.memory.allocator);
    var window = temp_arena.allocator().create(Window) catch |err| {
        temp_arena.deinit();
        return err;
    };

    window.* = Window{
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
                .popup = false,
            },
        },
        .node = .{ .data = {} },
        .title = undefined,
    };
    errdefer window.memory.deinit();

    const allocator = window.memory.allocator();

    window.title = std.ArrayList(u8).init(allocator);
    try window.title.ensureTotalCapacity(64);

    const pixel_count = @as(usize, window.user_facing.max_size.height) * @as(usize, window.user_facing.stride);
    window.user_facing.pixels = (try allocator.alloc(u8, pixel_count)).ptr;
    std.mem.set(u8, window.user_facing.pixels[0..pixel_count], 4); // brown

    const clamped_initial_size = sizeMax(sizeMin(initial_size, window.user_facing.max_size), window.user_facing.min_size);

    window.user_facing.client_rectangle = Rectangle{
        .x = 16,
        .y = 16,
        .width = clamped_initial_size.width,
        .height = clamped_initial_size.height,
    };

    if (windows.last) |top| blk: {
        const top_window = nodeToWindow(top);

        var spawn_x = top_window.user_facing.client_rectangle.x + 16;
        var spawn_y = top_window.user_facing.client_rectangle.y + 16;

        if (spawn_x + @as(i17, top_window.user_facing.client_rectangle.width) >= framebuffer.width)
            break :blk;
        if (spawn_y + @as(i17, top_window.user_facing.client_rectangle.height) >= framebuffer.height)
            break :blk;

        window.user_facing.client_rectangle.x = spawn_x;
        window.user_facing.client_rectangle.y = spawn_y;
    }

    try window.title.appendSlice(title);
    try window.title.append(0);

    window.user_facing.title = window.title.items[0 .. window.title.items.len - 1 :0];

    // TODO: Setup

    windows.append(&window.node);
    return window;
}

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

    const fb = ashet.video.memory[0 .. width * height];

    fn setPixel(x: i16, y: i16, color: ColorIndex) void {
        if (x < 0 or y < 0 or x >= width or y >= height) return;
        const ux = @intCast(u16, x);
        const uy = @intCast(u16, y);
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
                if (pix) |c| {
                    setPixel(x + @intCast(i16, dx), y + @intCast(i16, dy), c);
                }
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

    pub const minimize = parse(
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

    pub const maximize = parse(
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
    pub const cursor = parse(
        \\
    );
};
