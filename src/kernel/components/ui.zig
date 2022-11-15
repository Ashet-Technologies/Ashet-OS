const std = @import("std");
const ashet = @import("../main.zig");

const Size = ashet.abi.Size;
const Point = ashet.abi.Point;
const Rectangle = ashet.abi.Rectangle;

const framebuffer = struct {
    const width = ashet.video.max_res_x;
    const height = ashet.video.max_res_y;

    const fb = ashet.video.memory[0 .. width * height];

    inline fn setPixel(x: i16, y: i16, color: u8) void {
        if (x < 0 or y < 0 or x >= width or y >= height) return;
        const ux = @intCast(u16, x);
        const uy = @intCast(u16, y);
        fb[uy * width + ux] = color;
    }

    inline fn horizontalLine(x: i16, y: i16, w: u16, color: u8) void {
        var i: u15 = 0;
        while (i < w) : (i += 1) {
            setPixel(x + i, y, color);
        }
    }

    inline fn verticalLine(x: i16, y: i16, h: u16, color: u8) void {
        var i: u15 = 0;
        while (i < h) : (i += 1) {
            setPixel(x, y + i, color);
        }
    }

    fn clear(color: u8) void {
        std.mem.set(u8, fb, color);
    }
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
    _ = createWindow("Bottom", Size.init(0, 0), Size.init(400, 300), Size.init(200, 100)) catch @panic("oom");
    _ = createWindow("Middle", Size.init(0, 0), Size.init(400, 300), Size.init(160, 80)) catch @panic("oom");
    _ = createWindow("Top", Size.init(0, 0), Size.init(400, 300), Size.init(160, 80)) catch @panic("oom");

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
    ashet.video.setBorder(0);
    ashet.video.setResolution(framebuffer.width, framebuffer.height);
}

fn repaint() void {
    framebuffer.clear(0);

    var iter = WindowIterator.init();
    while (iter.next()) |window| {
        const client_rectangle = window.user_facing.client_rectangle;
        const window_rectangle = expandClientRectangle(client_rectangle);

        const border_color: u8 = if (window.user_facing.flags.focus)
            14
        else
            15;

        framebuffer.horizontalLine(window_rectangle.x, window_rectangle.y, window_rectangle.width, border_color);
        framebuffer.verticalLine(window_rectangle.x, window_rectangle.y + 1, window_rectangle.height - 1, border_color);

        framebuffer.horizontalLine(window_rectangle.x, window_rectangle.y + @intCast(i16, window_rectangle.height) - 1, window_rectangle.width, border_color);
        framebuffer.verticalLine(window_rectangle.x + @intCast(i16, window_rectangle.width) - 1, window_rectangle.y + 1, window_rectangle.height - 1, border_color);

        framebuffer.horizontalLine(window_rectangle.x + 1, window_rectangle.y + 10, window_rectangle.width - 2, border_color);

        var dy: u15 = 0;
        var row_ptr = window.user_facing.pixels;
        while (dy < client_rectangle.height) : (dy += 1) {
            var dx: u15 = 0;
            while (dx < client_rectangle.width) : (dx += 1) {
                framebuffer.setPixel(client_rectangle.x + dx, client_rectangle.y + dy, row_ptr[dx]);
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

    pub fn isResizable(window: Window) bool {
        return (window.user_facing.min_size.width != window.user_facing.max_size.width) or
            (window.user_facing.min_size.height != window.user_facing.max_size.height);
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
    std.mem.set(u8, window.user_facing.pixels[0..pixel_count], 3);

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
