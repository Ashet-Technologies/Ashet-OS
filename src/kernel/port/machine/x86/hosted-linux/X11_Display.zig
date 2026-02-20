//!
//! X11 Video Output Backend
//!
//! Links:
//!     - https://www.x.org/releases/X11R7.7/doc/xproto/x11protocol.html#events:input
//!
const std = @import("std");
const x11 = @import("x11");
const evdev = @import("../../../../drivers/input/evdev.zig");

const ashet = @import("../../../../main.zig");

const logger = std.log.scoped(.x11_display);

const X11_Display = @This();

allocator: std.mem.Allocator,
index: usize,

// x11 stuff:
socket_read_buffer: []u8,
socket_write_buffer: []u8,
socket_reader: x11.Stream15.Reader,
socket_writer: x11.Stream15.Writer,
source: x11.Source,
sink: x11.RequestSink,
setup: x11.Setup,
depth: x11.Depth,

window_id: x11.Window,

bg_gc_id: x11.GraphicsContext,

running: bool = true,

// helper types:

put_image_msg_buffer: []align(4) u8,
put_image_chunk_height: u16,

// devices:
screen: ashet.drivers.video.Host_VNC_Output,
// input: ashet.drivers.input.Host_SDL_Input,

pub fn init(
    allocator: std.mem.Allocator,
    index: usize,
    window_width: u16,
    window_height: u16,
) !*X11_Display {
    try x11.wsaStartup();

    const server = try allocator.create(X11_Display);
    errdefer allocator.destroy(server);

    const io_buffer_size = std.mem.alignForward(usize, 1000, std.heap.page_size_min);

    const socket_read_buffer = try allocator.alloc(u8, io_buffer_size);
    errdefer allocator.free(socket_read_buffer);
    const socket_write_buffer = try allocator.alloc(u8, io_buffer_size);
    errdefer allocator.free(socket_write_buffer);

    var socket_reader, const used_auth = try x11.draft.connect(socket_read_buffer);
    errdefer x11.disconnect(socket_reader.getStream());
    _ = used_auth;

    const setup = try x11.readSetupSuccess(socket_reader.interface());
    var setup_source = x11.Source.initFinishSetup(socket_reader.interface(), &setup);
    const screen = try x11.draft.readSetupDynamic(&setup_source, &setup, .{}) orelse {
        logger.err("no screen?", .{});
        std.process.exit(0xff);
    };

    const depth = x11.Depth.init(screen.root_depth) orelse {
        logger.err("unsupported root depth {}", .{screen.root_depth});
        std.process.exit(0xff);
    };

    const socket_writer = x11.socketWriter(socket_reader.getStream(), socket_write_buffer);

    const put_image_chunk_height: u16 = blk: {
        const static_overhead = x11.put_image.getLen(0);

        const max_message_size = std.math.maxInt(u18) - static_overhead;

        const scanline_size = 4 * @as(u18, window_width);

        const chunk_height: u16 = @intCast(max_message_size / scanline_size);

        logger.info("max message size: {}", .{max_message_size});
        logger.info("scanline size:    {}", .{scanline_size});
        logger.info("chunk height:     {}", .{chunk_height});

        break :blk chunk_height;
    };

    server.* = .{
        .allocator = allocator,
        .index = index,

        .screen = try .init(window_width, window_height),
        // .input = ashet.drivers.input.Host_SDL_Input.init(),

        .socket_read_buffer = socket_read_buffer,
        .socket_write_buffer = socket_write_buffer,
        .socket_reader = socket_reader,
        .socket_writer = socket_writer,
        .source = undefined,
        .sink = undefined,
        .setup = setup,
        .depth = depth,

        .put_image_chunk_height = put_image_chunk_height,
        .put_image_msg_buffer = try allocator.alignedAlloc(
            u8,
            .@"4", // alignment
            @as(usize, window_width) * @as(usize, put_image_chunk_height) * 4,
        ),

        .window_id = .none,
        .bg_gc_id = .none,
    };
    server.source = x11.Source.initAfterSetup(server.socket_reader.interface());
    server.sink = .{ .writer = &server.socket_writer.interface };

    @memset(server.screen.frontbuffer, ashet.abi.Color.blue);
    @memset(server.screen.backbuffer, ashet.abi.Color.red);

    const base_resource = server.setup.resource_id_base;

    server.window_id = base_resource.add(0).window();
    try server.sink.CreateWindow(.{
        .window_id = server.window_id,
        .parent_window_id = screen.root,
        .depth = 0, // inherit from the parent
        .x = 0,
        .y = 0,
        .width = window_width,
        .height = window_height,
        .border_width = 0,
        .class = .input_output,
        .visual_id = screen.root_visual,
    }, .{
        .bg_pixel = 0xaabbccdd,
        .event_mask = .{
            .KeyPress = 1,
            .KeyRelease = 1,
            .ButtonPress = 1,
            .ButtonRelease = 1,
            .EnterWindow = 1,
            .LeaveWindow = 1,
            .PointerMotion = 1,
            .PointerMotionHint = 0,
            .Button1Motion = 0,
            .Button2Motion = 0,
            .Button3Motion = 0,
            .Button4Motion = 0,
            .Button5Motion = 0,
            .ButtonMotion = 0,
            .KeymapState = 1,
            .Exposure = 1,
        },
    });

    server.bg_gc_id = base_resource.add(1).graphicsContext();
    try server.sink.CreateGc(
        server.bg_gc_id,
        server.window_id.drawable(),
        .{
            .foreground = screen.black_pixel,
        },
    );

    try server.sink.MapWindow(server.window_id);
    try server.sink.writer.flush();

    return server;
}

pub fn process_events_wrapper(server_ptr: ?*anyopaque) callconv(.c) u32 {
    const server: *X11_Display = @ptrCast(@alignCast(server_ptr.?));

    server.process_events() catch |err| {
        logger.err("failed to process X11 events: {}", .{err});
        @panic("Processing X11 events failed!");
    };

    std.posix.exit(0); // X11 connection closed.
}

pub fn process_events(server: *X11_Display) !void {
    while (server.running) {

        // Wait for socket ready:
        while (true) {
            try server.render_on_demand();

            if (server.source.reader.seek < server.source.reader.end)
                break;

            var pfd: [1]std.posix.pollfd = .{
                .{
                    .fd = server.socket_reader.getStream().handle,
                    .events = std.posix.POLL.IN,
                    .revents = 0,
                },
            };
            _ = try std.posix.poll(&pfd, 0);

            if ((pfd[0].revents & (std.posix.POLL.IN | std.posix.POLL.ERR)) != 0)
                break;

            ashet.scheduler.yield();
        }

        const msg_kind = server.source.readKind() catch |err| switch (err) {
            error.EndOfStream => {
                logger.info("X server connection closed", .{});
                server.running = false;
                return;
            },
            else => return err,
        };

        switch (msg_kind) {
            .Error => {
                const msg = try server.source.read2(.Error);
                logger.err("{f}", .{msg});
                return error.X11Error;
            },
            .Reply => {
                const msg = try server.source.read2(.Reply);
                logger.warn("todo: handle a reply message sequence={} words={} flex={}", .{
                    msg.sequence,
                    msg.word_count,
                    msg.flexible,
                });
                try server.source.discardRemaining();
                return error.TodoHandleReplyMessage;
            },
            .KeyPress => {
                const msg = try server.source.read2(.KeyPress);
                logger.debug("key_press: keycode={}", .{msg.keycode});
                try server.handle_key_event(msg.keycode, true);
            },
            .KeyRelease => {
                const msg = try server.source.read2(.KeyRelease);
                logger.debug("key_release: keycode={}", .{msg.keycode});
                try server.handle_key_event(msg.keycode, false);
            },
            .ButtonPress => {
                const msg = try server.source.read2(.ButtonPress);
                logger.debug("button_press: {}", .{msg});
                try server.handle_mouse_button_event(msg.button, true);
            },
            .ButtonRelease => {
                const msg = try server.source.read2(.ButtonRelease);
                logger.debug("button_release: {}", .{msg});
                try server.handle_mouse_button_event(msg.button, false);
            },
            .EnterNotify => {
                const msg = try server.source.read2(.EnterNotify);
                logger.info("enter_window: {}", .{msg});
            },
            .LeaveNotify => {
                const msg = try server.source.read2(.LeaveNotify);
                logger.info("leave_window: {}", .{msg});
            },
            .MotionNotify => {
                const msg = try server.source.read2(.MotionNotify);
                logger.debug("pointer_motion: {}", .{msg});
                try server.handle_mouse_motion_event(msg.event_x, msg.event_y);
            },
            .KeymapNotify => {
                const msg = try server.source.read2(.KeymapNotify);
                logger.info("keymap_state: {}", .{msg});
            },
            .Expose => {
                const msg = try server.source.read2(.Expose);
                logger.debug("expose: {}", .{msg});
                try server.force_render();
            },
            .MappingNotify => {
                const msg = try server.source.read2(.MappingNotify);
                logger.info("mapping_notify: {}", .{msg});
            },
            .NoExposure => {
                const msg = try server.source.read2(.NoExposure);
                std.debug.panic("unexpected no_exposure {}", .{msg});
            },
            .GenericEvent => {
                const msg = try server.source.read2(.GenericEvent);
                logger.warn("todo: server msg generic_event opcode_base={} type={} words={}", .{
                    msg.ext_opcode_base,
                    msg.type,
                    msg.word_count,
                });
                try server.source.discardRemaining();
                return error.UnhandledServerMsg;
            },
            .UnknownCoreEvent, .ExtensionEvent => |value| {
                logger.warn("todo: server msg {}", .{value});
                return error.UnhandledServerMsg;
            },
            .MapNotify, .ReparentNotify, .ConfigureNotify => unreachable, // did not register for these
            else => |tag| {
                logger.warn("todo: server msg {s}", .{@tagName(tag)});
                return error.UnhandledServerMsg;
            },
        }
    }
}

fn handle_mouse_motion_event(server: *X11_Display, event_x: i16, event_y: i16) !void {
    _ = server;
    ashet.input.push_raw_event(.{
        .mouse_abs_motion = .{
            .x = event_x,
            .y = event_y,
        },
    });
}

fn handle_key_event(server: *X11_Display, keycode: u8, is_press: bool) !void {

    // Adjust "key code" to "scancode" by adjusting to "min_keycode".
    // On Xpra, Escape maps to "9" and "min_keycode" is 8, which maps to "1" which is the expected value.
    const min_keycode = server.setup.min_keycode;
    if (keycode < min_keycode) {
        logger.warn("received invalid keycode: expected at least {}, but received {}", .{
            min_keycode,
            keycode,
        });
        return;
    }

    const scancode: u16 = @as(u16, keycode) - server.setup.min_keycode;

    if (evdev.keyFromEvdev(scancode)) |usage| {
        ashet.input.push_raw_event(.{
            .keyboard = .{
                .usage = usage,
                .down = is_press,
            },
        });
    } else {
        logger.warn("received unknown evdev keycode: {}", .{scancode});
    }
}

fn handle_mouse_button_event(server: *X11_Display, button: u8, is_press: bool) !void {
    _ = server;

    const mouse_button: ashet.abi.MouseButton = switch (button) {
        // See https://github.com/torvalds/linux/blob/master/include/uapi/linux/input-event-codes.h#L762
        1 => .left,
        2 => .middle,
        3 => .right,
        4 => .wheel_up,
        5 => .wheel_down,
        6, 8 => .nav_previous,
        7, 9 => .nav_next,
        else => {
            logger.warn("unsupported mouse button: {d}", .{button});
            return;
        },
    };

    ashet.input.push_raw_event(.{
        .mouse_button = .{
            .button = mouse_button,
            .down = is_press,
        },
    });
}

fn render_on_demand(server: *X11_Display) !void {
    defer std.debug.assert(server.screen.backbuffer_dirty == false);

    if (server.screen.backbuffer_dirty) {
        try server.force_render();
    }
}

fn force_render(server: *X11_Display) !void {
    defer server.screen.backbuffer_dirty = false;

    // Put window content in chunks, as we can't transfer full images
    // as X11 has only maxInt(u18)

    var source_pixels: [*]const ashet.abi.Color = server.screen.backbuffer.ptr;

    var base_y: u16 = 0;
    while (base_y < server.screen.height) : (base_y += server.put_image_chunk_height) { // BB GG RR XX
        const chunk_height = @min(server.screen.height - base_y, server.put_image_chunk_height);
        const chunk_size: u18 = @as(u18, 4) * @as(u18, chunk_height) * @as(u18, server.screen.width);

        const chunk_pixels: usize = @as(usize, chunk_height) * server.screen.width;

        // logger.info("chunk base={}, height={}, size={}, pixels={}", .{
        //     base_y,
        //     chunk_height,
        //     chunk_size,
        //     chunk_pixels,
        // });

        const chunk_size_usize: usize = @intCast(chunk_size);
        const pixel_bytes = server.put_image_msg_buffer[0..chunk_size_usize];
        const pixel_data: []u32 = @ptrCast(@alignCast(pixel_bytes));

        std.debug.assert(pixel_data.len == @divExact(chunk_size_usize, 4));

        const pad_len = try server.sink.PutImageStart(chunk_size, .{
            .format = .z_pixmap,
            .drawable = server.window_id.drawable(),
            .gc_id = server.bg_gc_id,
            .width = server.screen.width,
            .height = chunk_height,
            .x = 0,
            .y = @intCast(base_y),
            .depth = server.depth,
        });

        for (pixel_data, source_pixels[0..chunk_pixels]) |*out, in| {
            out.* = @intFromEnum(in.to_argb8888()); // 0x??RRGGBB
        }
        source_pixels += chunk_pixels;

        try server.sink.writer.writeAll(pixel_bytes);
        try server.sink.PutImageFinish(pad_len);
    }
    try server.sink.writer.flush();
}
