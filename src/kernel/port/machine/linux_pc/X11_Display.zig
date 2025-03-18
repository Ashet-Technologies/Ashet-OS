//!
//! X11 Video Output Backend
//!
//! Links:
//!     - https://www.x.org/releases/X11R7.7/doc/xproto/x11protocol.html#events:input
//!
const std = @import("std");
const x11 = @import("x11");

const ashet = @import("../../../main.zig");

const logger = std.log.scoped(.x11_display);

const X11_Display = @This();

allocator: std.mem.Allocator,
index: usize,

// x11 stuff:

double_buf: x11.DoubleBuffer,

sock: std.posix.socket_t,
setup: x11.ConnectSetup,

sequence: u16 = 0,
window_id: u32,

bg_gc_id: u32,

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

    const display = x11.getDisplay();

    const parsed_display = x11.parseDisplay(display) catch |err| {
        logger.err("invalid display '{s}': {s}", .{ display, @errorName(err) });
        std.process.exit(0xff);
    };

    const sock = x11.connect(display, parsed_display) catch |err| {
        logger.err("failed to connect to display '{s}': {s}", .{ display, @errorName(err) });
        std.process.exit(0xff);
    };
    errdefer x11.disconnect(sock);

    const server = try allocator.create(X11_Display);
    errdefer allocator.destroy(server);

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

        .double_buf = try x11.DoubleBuffer.init(
            std.mem.alignForward(usize, 1000, std.heap.page_size_min),
            .{ .memfd_name = "ZigX11DoubleBuffer" },
        ),

        .put_image_chunk_height = put_image_chunk_height,
        .put_image_msg_buffer = try allocator.alignedAlloc(
            u8,
            4, // alignment
            x11.put_image.getLen(4 * @as(u18, window_width) * put_image_chunk_height),
        ),

        .sock = sock,
        .setup = undefined,

        .window_id = 0,
        .bg_gc_id = 0,
    };
    logger.info("read buffer capacity is {}", .{server.double_buf.half_len});

    const setup_reply_len: u16 = blk: {
        if (try x11.getAuthFilename(allocator)) |auth_filename| {
            defer auth_filename.deinit(allocator);
            if (try server.connectSetupAuth(parsed_display.display_num, auth_filename.str)) |reply_len|
                break :blk reply_len;
        }

        // Try no authentication
        logger.debug("trying no auth", .{});
        var msg_buf: [x11.connect_setup.getLen(0, 0)]u8 = undefined;
        if (try server.connectSetup(
            &msg_buf,
            .{ .ptr = undefined, .len = 0 },
            .{ .ptr = undefined, .len = 0 },
        )) |reply_len| {
            break :blk reply_len;
        }

        logger.err("the X server rejected our connect setup message", .{});
        std.process.exit(0xff);
    };

    const connect_setup = x11.ConnectSetup{
        .buf = try allocator.allocWithOptions(u8, setup_reply_len, 4, null),
    };
    logger.debug("connect setup reply is {} bytes", .{connect_setup.buf.len});
    try x11.readFull(SocketReader{ .context = sock }, connect_setup.buf);

    server.setup = connect_setup;

    @memset(server.screen.frontbuffer, ashet.abi.Color.blue);
    @memset(server.screen.backbuffer, ashet.abi.Color.red);

    errdefer std.posix.shutdown(server.sock, .both) catch {};

    const screen = blk: {
        const fixed = server.setup.fixed();

        inline for (@typeInfo(@TypeOf(fixed.*)).@"struct".fields) |field| {
            logger.debug("{s}: {any}", .{ field.name, @field(fixed, field.name) });
        }

        logger.debug("vendor: {s}", .{try server.setup.getVendorSlice(fixed.vendor_len)});
        const format_list_offset = x11.ConnectSetup.getFormatListOffset(fixed.vendor_len);
        const format_list_limit = x11.ConnectSetup.getFormatListLimit(format_list_offset, fixed.format_count);
        logger.debug("fmt list off={} limit={}", .{ format_list_offset, format_list_limit });
        const formats = try server.setup.getFormatList(format_list_offset, format_list_limit);
        for (formats, 0..) |format, i| {
            logger.debug("  format[{}] depth={:3} bpp={:3} scanpad={:3}", .{ i, format.depth, format.bits_per_pixel, format.scanline_pad });
        }

        const screen = server.setup.getFirstScreenPtr(format_list_limit);
        inline for (@typeInfo(@TypeOf(screen.*)).@"struct".fields) |field| {
            logger.debug("SCREEN 0| {s}: {any}", .{ field.name, @field(screen, field.name) });
        }

        break :blk screen;
    };

    // TODO: maybe need to call conn.setup.verify or something?

    server.window_id = server.setup.fixed().resource_id_base;
    {
        var msg_buf: [x11.create_window.max_len]u8 = undefined;
        const len = x11.create_window.serialize(&msg_buf, .{
            .window_id = server.window_id,
            .parent_window_id = screen.root,
            .depth = 24, // we don't care, just inherit from the parent
            .x = 0,
            .y = 0,
            .width = window_width,
            .height = window_height,
            .border_width = 0, // TODO: what is this?
            .class = .input_output,
            .visual_id = screen.root_visual,
        }, .{
            //            .bg_pixmap = .copy_from_parent,
            .bg_pixel = 0xaabbccdd,
            //            //.border_pixmap =
            //            .border_pixel = 0x01fa8ec9,
            //            .bit_gravity = .north_west,
            //            .win_gravity = .east,
            //            .backing_store = .when_mapped,
            //            .backing_planes = 0x1234,
            //            .backing_pixel = 0xbbeeeeff,
            //            .override_redirect = true,
            //            .save_under = true,
            .event_mask = x11.event.key_press | x11.event.key_release | x11.event.button_press | x11.event.button_release | x11.event.enter_window | x11.event.leave_window | x11.event.pointer_motion
                //                | x11.event.pointer_motion_hint WHAT THIS DO?
                //                | x11.event.button1_motion  WHAT THIS DO?
                //                | x11.event.button2_motion  WHAT THIS DO?
                //                | x11.event.button3_motion  WHAT THIS DO?
                //                | x11.event.button4_motion  WHAT THIS DO?
                //                | x11.event.button5_motion  WHAT THIS DO?
                //                | x11.event.button_motion  WHAT THIS DO?
            | x11.event.keymap_state | x11.event.exposure,
            //            .dont_propagate = 1,
        });
        try server.sendOne(msg_buf[0..len]);
    }

    server.bg_gc_id = server.window_id + 1;
    {
        var msg_buf: [x11.create_gc.max_len]u8 = undefined;
        const len = x11.create_gc.serialize(&msg_buf, .{
            .gc_id = server.bg_gc_id,
            .drawable_id = server.window_id,
        }, .{
            .foreground = screen.black_pixel,
        });
        try server.sendOne(msg_buf[0..len]);
    }

    {
        var msg: [x11.map_window.len]u8 = undefined;
        x11.map_window.serialize(&msg, server.window_id);
        try server.sendOne(&msg);
    }

    return server;
}

pub fn process_events_wrapper(server_ptr: ?*anyopaque) callconv(.C) u32 {
    const server: *X11_Display = @ptrCast(@alignCast(server_ptr.?));

    server.process_events() catch |err| {
        logger.err("failed to process X11 events: {}", .{err});
        @panic("Processing X11 events failed!");
    };

    std.posix.exit(0); // X11 connection closed.
}

pub fn process_events(server: *X11_Display) !void {
    var buf = server.double_buf.contiguousReadBuffer();
    while (server.running) {

        // Wait for socket ready:
        while (true) {
            try server.render_on_demand();

            var pfd: [1]std.posix.pollfd = .{
                .{
                    .fd = server.sock,
                    .events = std.posix.POLL.IN,
                    .revents = 0,
                },
            };
            _ = try std.posix.poll(&pfd, 0);

            if ((pfd[0].revents & (std.posix.POLL.IN | std.posix.POLL.ERR)) != 0)
                break;

            ashet.scheduler.yield();
        }

        {
            const recv_buf = buf.nextReadBuffer();
            if (recv_buf.len == 0) {
                logger.err("buffer size {} not big enough!", .{buf.half_len});
                return error.BufferSize;
            }
            const len = try x11.readSock(server.sock, recv_buf, 0);
            if (len == 0) {
                logger.info("X server connection closed", .{});
                server.running = false;
                return;
            }
            buf.reserve(len);
        }

        while (true) {
            const data = buf.nextReservedBuffer();
            if (data.len < 32)
                break;
            const msg_len = x11.parseMsgLen(data[0..32].*);
            if (data.len < msg_len)
                break;
            buf.release(msg_len);
            //buf.resetIfEmpty();
            switch (x11.serverMsgTaggedUnion(@alignCast(data.ptr))) {
                .err => |msg| {
                    logger.err("{}", .{msg});
                    return error.X11Error;
                },
                .reply => |msg| {
                    logger.warn("todo: handle a reply message {}", .{msg});
                    return error.TodoHandleReplyMessage;
                },
                .key_press => |msg| {
                    logger.debug("key_press: keycode={}", .{msg});
                    try server.handle_key_event(msg.*, true);
                },
                .key_release => |msg| {
                    logger.debug("key_release: keycode={}", .{msg});
                    try server.handle_key_event(msg.*, false);
                },
                .button_press => |msg| {
                    logger.debug("button_press: {}", .{msg});
                    try server.handle_mouse_button_event(msg.*, true);
                },
                .button_release => |msg| {
                    logger.debug("button_release: {}", .{msg});
                    try server.handle_mouse_button_event(msg.*, false);
                },
                .enter_notify => |msg| {
                    logger.info("enter_window: {}", .{msg});
                },
                .leave_notify => |msg| {
                    logger.info("leave_window: {}", .{msg});
                },
                .motion_notify => |msg| {
                    // too much logging
                    logger.debug("pointer_motion: {}", .{msg});
                    try server.handle_mouse_motion_event(msg.*);
                },
                .keymap_notify => |msg| {
                    logger.info("keymap_state: {}", .{msg});
                },
                .expose => |msg| {
                    logger.debug("expose: {}", .{msg});
                    try server.force_render();
                },
                .mapping_notify => |msg| {
                    logger.info("mapping_notify: {}", .{msg});
                },
                .no_exposure => |msg| std.debug.panic("unexpected no_exposure {}", .{msg}),
                .unhandled => |msg| {
                    logger.warn("todo: server msg {}", .{msg});
                    return error.UnhandledServerMsg;
                },
                .map_notify,
                .reparent_notify,
                .configure_notify,
                => unreachable, // did not register for these
            }
        }
    }
}

fn handle_mouse_motion_event(server: *X11_Display, event: x11.Event.KeyOrButtonOrMotion) !void {
    _ = server;
    ashet.input.push_raw_event(.{
        .mouse_abs_motion = .{
            .x = event.event_x,
            .y = event.event_y,
        },
    });
}

fn handle_key_event(server: *X11_Display, event: x11.Event.Key, is_press: bool) !void {
    _ = server;
    _ = event;
    _ = is_press;
}

fn handle_mouse_button_event(server: *X11_Display, event: x11.Event.KeyOrButtonOrMotion, is_press: bool) !void {
    _ = server;

    const mouse_button: ashet.abi.MouseButton = switch (event.detail) {
        // See https://github.com/torvalds/linux/blob/master/include/uapi/linux/input-event-codes.h#L762
        1 => .left,
        2 => .middle,
        3 => .right,
        4 => .wheel_up,
        5 => .wheel_down,
        6, 8 => .nav_previous,
        7, 9 => .nav_next,
        else => {
            logger.warn("unsupported mouse button: {d}", .{event.detail});
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

        comptime std.debug.assert(std.mem.isAligned(x11.put_image.data_offset, 4));
        const pixel_data: []u32 = @ptrCast(@alignCast(server.put_image_msg_buffer[x11.put_image.data_offset..][0..chunk_size]));

        std.debug.assert(pixel_data.len == @divExact(chunk_size, 4));

        const msg_len = x11.put_image.getLen(chunk_size);
        x11.put_image.serializeNoDataCopy(server.put_image_msg_buffer.ptr, chunk_size, .{
            .drawable_id = server.window_id,
            .depth = 24,
            .format = .z_pixmap,
            .gc_id = server.bg_gc_id,
            .x = 0,
            .y = @intCast(base_y),
            .width = server.screen.width,
            .height = chunk_height,
            .left_pad = 0,
        });

        for (pixel_data, source_pixels[0..chunk_pixels]) |*out, in| {
            out.* = @intFromEnum(in.to_argb8888()); // 0x??RRGGBB
        }
        source_pixels += chunk_pixels;

        try server.sendOne(server.put_image_msg_buffer[0..msg_len]);
    }
}

fn get_reader(server: *X11_Display) SocketReader {
    return .{ .context = server.sock };
}

const SocketReader = std.io.Reader(std.posix.socket_t, std.posix.RecvFromError, readSocket);

/// Sanity check that we're not running into data integrity (corruption) issues caused
/// by overflowing and wrapping around to the front ofq the buffer.
fn checkMessageLengthFitsInBuffer(message_length: usize, buffer_limit: usize) !void {
    if (message_length > buffer_limit) {
        std.debug.panic("Reply is bigger than our buffer (data corruption will ensue) {} > {}. In order to fix, increase the buffer size.", .{
            message_length,
            buffer_limit,
        });
    }
}

fn sendOne(server: *X11_Display, data: []const u8) !void {
    try server.sendNoSequencing(data);
    server.sequence +%= 1;
}

fn sendNoSequencing(server: *X11_Display, data: []const u8) !void {
    const sent = try x11.writeSock(server.sock, data, 0);
    if (sent != data.len) {
        logger.err("send {} only sent {}\n", .{ data.len, sent });
        return error.DidNotSendAllData;
    }
}

fn connectSetupMaxAuth(
    server: *X11_Display,
    comptime max_auth_len: usize,
    auth_name: x11.Slice(u16, [*]const u8),
    auth_data: x11.Slice(u16, [*]const u8),
) !?u16 {
    var buf: [x11.connect_setup.auth_offset + max_auth_len]u8 = undefined;
    const len = x11.connect_setup.getLen(auth_name.len, auth_data.len);
    if (len > max_auth_len)
        return error.AuthTooBig;
    return server.connectSetup(buf[0..len], auth_name, auth_data);
}

fn connectSetup(
    server: *X11_Display,
    msg: []u8,
    auth_name: x11.Slice(u16, [*]const u8),
    auth_data: x11.Slice(u16, [*]const u8),
) !?u16 {
    std.debug.assert(msg.len == x11.connect_setup.getLen(auth_name.len, auth_data.len));

    x11.connect_setup.serialize(msg.ptr, 11, 0, auth_name, auth_data);
    try server.sendNoSequencing(msg);

    const reader = server.get_reader();
    const connect_setup_header = try x11.readConnectSetupHeader(reader, .{});
    switch (connect_setup_header.status) {
        .failed => {
            logger.err("connect setup failed, version={}.{}, reason='{s}'", .{
                connect_setup_header.proto_major_ver,
                connect_setup_header.proto_minor_ver,
                connect_setup_header.readFailReason(reader),
            });
            return error.ConnectSetupFailed;
        },
        .authenticate => {
            logger.err("AUTHENTICATE! not implemented", .{});
            return error.NotImplemetned;
        },
        .success => {
            // TODO: check version?
            logger.debug("SUCCESS! version {}.{}", .{ connect_setup_header.proto_major_ver, connect_setup_header.proto_minor_ver });
            return connect_setup_header.getReplyLen();
        },
        else => |status| {
            logger.err("Error: expected 0, 1 or 2 as first byte of connect setup reply, but got {}", .{status});
            return error.MalformedXReply;
        },
    }
}

fn connectSetupAuth(
    server: *X11_Display,
    display_num: ?u32,
    auth_filename: []const u8,
) !?u16 {
    // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    // TODO: test bad auth
    // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    //if (try connectSetupMaxAuth(sock, 1000, .{ .ptr = "wat", .len = 3}, .{ .ptr = undefined, .len = 0})) |_|
    //    @panic("todo");

    const auth_mapped = try x11.MappedFile.init(auth_filename, .{});
    defer auth_mapped.unmap();

    var auth_filter = x11.AuthFilter{
        .addr = .{ .family = .wild, .data = &[0]u8{} },
        .display_num = display_num,
    };

    var addr_buf: [x11.max_sock_filter_addr]u8 = undefined;
    if (auth_filter.applySocket(server.sock, &addr_buf)) {
        logger.debug("applied address filter {}", .{auth_filter.addr});
    } else |err| {
        // not a huge deal, we'll just try all auth methods
        logger.warn("failed to apply socket to auth filter with {s}", .{@errorName(err)});
    }

    var auth_it = x11.AuthIterator{ .mem = auth_mapped.mem };
    while (auth_it.next() catch {
        logger.warn("auth file '{s}' is invalid", .{auth_filename});
        return null;
    }) |entry| {
        if (auth_filter.isFiltered(auth_mapped.mem, entry)) |reason| {
            logger.debug("ignoring auth because {s} does not match: {}", .{ @tagName(reason), entry.fmt(auth_mapped.mem) });
            continue;
        }
        const name = entry.name(auth_mapped.mem);
        const data = entry.data(auth_mapped.mem);
        const name_x = x11.Slice(u16, [*]const u8){
            .ptr = name.ptr,
            .len = @intCast(name.len),
        };
        const data_x = x11.Slice(u16, [*]const u8){
            .ptr = data.ptr,
            .len = @intCast(data.len),
        };
        logger.debug("trying auth {}", .{entry.fmt(auth_mapped.mem)});
        if (try server.connectSetupMaxAuth(1000, name_x, data_x)) |reply_len|
            return reply_len;
    }

    return null;
}

pub fn asReply(comptime T: type, msg_bytes: []align(4) u8) !*T {
    const generic_msg: *x11.ServerMsg.Generic = @ptrCast(msg_bytes.ptr);
    if (generic_msg.kind != .reply) {
        logger.err("expected reply but got {}", .{generic_msg});
        return error.UnexpectedReply;
    }
    return @alignCast(@ptrCast(generic_msg));
}

fn readSocket(sock: std.posix.socket_t, buffer: []u8) !usize {
    return x11.readSock(sock, buffer, 0);
}

/// X server extension info.
pub const ExtensionInfo = struct {
    extension_name: []const u8,
    /// The extension opcode is used to identify which X extension a given request is
    /// intended for (used as the major opcode). This essentially namespaces any extension
    /// requests. The extension differentiates its own requests by using a minor opcode.
    opcode: u8,
    /// Extension error codes are added on top of this base error code.
    base_error_code: u8,
};

pub const ExtensionVersion = struct {
    major_version: u16,
    minor_version: u16,
};

/// Determines whether the extension is available on the server.
pub fn getExtensionInfo(
    sock: std.posix.socket_t,
    sequence: *u16,
    buffer: *x11.ContiguousReadBuffer,
    comptime extension_name: []const u8,
) !?ExtensionInfo {
    const reader = SocketReader{ .context = sock };
    const buffer_limit = buffer.half_len;

    {
        const ext_name = comptime x11.Slice(u16, [*]const u8).initComptime(extension_name);
        var message_buffer: [x11.query_extension.getLen(ext_name.len)]u8 = undefined;
        x11.query_extension.serialize(&message_buffer, ext_name);
        try sendOne(sock, sequence, &message_buffer);
    }
    const message_length = try x11.readOneMsg(reader, @alignCast(buffer.nextReadBuffer()));
    try checkMessageLengthFitsInBuffer(message_length, buffer_limit);
    const optional_extension = blk: {
        switch (x11.serverMsgTaggedUnion(@alignCast(buffer.double_buffer_ptr))) {
            .reply => |msg_reply| {
                const msg: *x11.ServerMsg.QueryExtension = @ptrCast(msg_reply);
                if (msg.present == 0) {
                    logger.info("{s} extension: not present", .{extension_name});
                    break :blk null;
                }
                std.debug.assert(msg.present == 1);
                logger.info("{s} extension: opcode={} base_error_code={}", .{
                    extension_name,
                    msg.major_opcode,
                    msg.first_error,
                });
                logger.info("{s} extension: {}", .{ extension_name, msg });
                break :blk ExtensionInfo{
                    .extension_name = extension_name,
                    .opcode = msg.major_opcode,
                    .base_error_code = msg.first_error,
                };
            },
            else => |msg| {
                logger.err("expected a reply for `x11.query_extension` but got {}", .{msg});
                return error.ExpectedReplyButGotSomethingElse;
            },
        }
    };

    return optional_extension;
}
