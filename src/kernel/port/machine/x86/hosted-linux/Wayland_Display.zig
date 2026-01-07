const std = @import("std");
const shimizu = @import("shimizu");
const wp = @import("wayland-protocols");
const wu = @import("wayland-unstable");

const zxdg_decoration_manager_v1 = wu.xdg_decoration_unstable_v1.zxdg_decoration_manager_v1;

const ashet = @import("../../../../main.zig");
const evdev = @import("../../../../drivers/input/evdev.zig");

const logger = std.log.scoped(.wayland_display);

const wayland = shimizu.core;
const xdg_shell = wp.xdg_shell;

const Wayland_Display = @This();

allocator: std.mem.Allocator,
index: usize,

connection: shimizu.posix.Connection,

wl_surface: wayland.wl_surface,

xdg_surface: xdg_shell.xdg_surface,
xdg_toplevel: xdg_shell.xdg_toplevel,

xdg_decorations_manager: ?zxdg_decoration_manager_v1,

wl_compositor: wayland.wl_compositor,
has_wl_compositor: bool = false,

xdg_wm_base: xdg_shell.xdg_wm_base,
has_xdg_wm_base: bool = false,

wl_shm: wayland.wl_shm,
has_wl_shm: bool = false,

seat: ?Seat = null,

// allocate a some framebuffers for rendering to
swap_chain: shimizu.posix.ShmSwapChain,

// state to keep track of while rendering
frame_count: u32 = 0,
should_render: bool = true,
running: bool = true,

// devices:
screen: ashet.drivers.video.Host_VNC_Output,
// input: ashet.drivers.input.Host_SDL_Input,

window_width: u31,
window_height: u31,

pub fn init(
    allocator: std.mem.Allocator,
    index: usize,
    width: u16,
    height: u16,
    initial_scale: u8,
) !*Wayland_Display {
    const server = try allocator.create(Wayland_Display);
    errdefer allocator.destroy(server);

    server.* = .{
        .allocator = allocator,
        .index = index,

        .screen = try .init(width, height),
        // .input = ashet.drivers.input.Host_SDL_Input.init(),

        .window_width = @max(1, initial_scale) * width,
        .window_height = @max(1, initial_scale) * height,

        .connection = undefined,
        .wl_surface = undefined,
        .xdg_surface = undefined,
        .xdg_toplevel = undefined,
        .xdg_decorations_manager = undefined,
        .wl_compositor = undefined,
        .xdg_wm_base = undefined,
        .wl_shm = undefined,

        .swap_chain = undefined,
    };

    @memset(server.screen.frontbuffer, ashet.abi.Color.blue);
    @memset(server.screen.backbuffer, ashet.abi.Color.red);

    server.connection = shimizu.posix.Connection.open(allocator, .{}) catch |err| switch (err) {
        error.FileNotFound => return error.NoWaylandSupport,
        error.XDGRuntimeDirEnvironmentVariableNotFound => return error.NoWaylandSupport,
        else => |e| return e,
    };
    errdefer server.connection.close();

    const connection = server.connection.connection();

    const display = server.connection.getDisplay();
    const registry = try display.get_registry(connection);
    const registry_done_callback = try display.sync(connection);

    try connection.setEventListener(registry, *Wayland_Display, onRegistryEvent, server);

    var registration_done = false;
    try connection.setEventListener(
        registry_done_callback,
        *bool,
        onWlCallbackSetTrue,
        &registration_done,
    );

    while (!registration_done) {
        try server.connection.recv();
    }

    if (!server.has_wl_compositor) return error.WlCompositorNotFound;
    if (!server.has_xdg_wm_base) return error.XdgWmBaseNotFound;
    if (!server.has_wl_shm) return error.WlShmNotFound;

    // set up a xdg_wm_base listener for the ping event
    try connection.setEventListener(server.xdg_wm_base, void, onXdgWmBaseEvent, {});

    server.wl_surface = try server.wl_compositor.create_surface(connection);
    server.xdg_surface = try server.xdg_wm_base.get_xdg_surface(connection, server.wl_surface);
    server.xdg_toplevel = try server.xdg_surface.get_toplevel(connection);

    try server.xdg_toplevel.set_app_id(connection, "computer.ashet.os");

    try server.wl_surface.commit(connection);

    var surface_configured = false;

    try connection.setEventListener(
        server.xdg_surface,
        *bool,
        onXdgSurfaceEvent,
        &surface_configured,
    );

    while (!surface_configured) {
        try server.connection.recv();
    }

    // allocate a some framebuffers for rendering to
    server.swap_chain = .{ .wl_shm = server.wl_shm };
    errdefer server.swap_chain.deinit(
        server.connection.connection(),
        allocator,
    );

    try connection.setEventListener(server.xdg_toplevel, *Wayland_Display, onXdgToplevelEvent, server);

    if (server.xdg_decorations_manager) |manager| {
        const decorations = try manager.get_toplevel_decoration(connection, server.xdg_toplevel);
        try decorations.set_mode(connection, .server_side);
    }

    return server;
}

pub fn process_events_wrapper(server_ptr: ?*anyopaque) callconv(.C) u32 {
    const server: *Wayland_Display = @ptrCast(@alignCast(server_ptr.?));

    server.process_events() catch |err| {
        logger.err("failed to process wayland events: {}", .{err});
        return 1;
    };
    return 0;
}

pub fn process_events(server: *Wayland_Display) !void {
    while (server.running) {
        if (server.should_render) {
            const framebuffer = try server.swap_chain.mapBuffer(
                server.connection.connection(),
                server.allocator,
                // (@as(u31, @sizeOf(Pixel)) * server.screen.width) * server.screen.height,
                @sizeOf(Pixel) * server.window_width * server.window_height,
            );
            errdefer server.swap_chain.unmapBuffer(framebuffer);

            const pixels = std.mem.bytesAsSlice(Pixel, framebuffer);

            server.copyFromDriver(pixels);

            const frame_callback = try server.wl_surface.frame(server.connection.connection());
            try server.connection.connection().setEventListener(frame_callback, *bool, onWlCallbackSetTrue, &server.should_render);

            const wl_buffer = try server.swap_chain.sendBuffer(
                server.connection.connection(),
                framebuffer,
                server.window_width,
                server.window_height,
                server.window_width * @sizeOf(Pixel),
                .argb8888,
            );

            try server.wl_surface.attach(server.connection.connection(), wl_buffer, 0, 0);
            try server.wl_surface.damage(server.connection.connection(), 0, 0, std.math.maxInt(i32), std.math.maxInt(i32));
            try server.wl_surface.commit(server.connection.connection());

            server.should_render = false;
            server.frame_count += 1;
        }

        // logger.info("tick  {}", .{server.frame_count});
        // try server.connection.recv();

        wait_loop: while (true) {
            try server.connection.flushSendBuffers();
            // TODO: switch to std.posix.recvmsg: https://github.com/ziglang/zig/issues/20660
            const bytes_read = std.os.linux.recvmsg(
                server.connection.socket,
                server.connection.getRecvMsgHdr(),
                std.posix.MSG.DONTWAIT,
            );
            const errno_id: isize = @bitCast(bytes_read);
            if (errno_id < 0) {
                const errno: std.posix.E = @enumFromInt(@as(u16, @intCast(-errno_id)));
                switch (errno) {
                    .AGAIN => {
                        ashet.scheduler.yield();
                        continue :wait_loop;
                    },
                    else => {
                        logger.err("failed to recvmsg: {}", .{errno});
                        return error.CommError;
                    },
                }
            } else {
                try server.connection.processRecvMsgReturn(bytes_read);
                break :wait_loop;
            }
        }
    }
    logger.err("window closed, stopping simulation!", .{});
    std.process.exit(0);
}

const palette_lut: [256]Pixel = blk: {
    @setEvalBranchQuota(10_000);
    var palette: [256]Pixel = undefined;
    for (&palette, 0..) |*rgb, index| {
        const index8: u8 = @intCast(index);
        const color: ashet.abi.Color = @bitCast(index8);
        rgb.* = color.to_argb8888();
    }

    break :blk palette;
};

fn get_content_scale(server: *Wayland_Display) u32 {
    const content_w: u32 = server.screen.width;
    const content_h: u32 = server.screen.height;
    const window_w = server.window_width;
    const window_h = server.window_height;

    const scale_x = window_w / content_w;
    const scale_y = window_h / content_h;

    return @min(scale_x, scale_y);
}

fn copyFromDriver(server: *Wayland_Display, pixels: []Pixel) void {
    // Clear the buffer to black for letterboxing
    @memset(pixels, @enumFromInt(0xFF000000));

    const content_w: u32 = server.screen.width;
    const content_h: u32 = server.screen.height;
    const window_w = server.window_width;
    const window_h = server.window_height;

    const scale = server.get_content_scale();
    if (scale == 0)
        return; // Window is smaller than content, do not render.

    const scaled_w = content_w * scale;
    const scaled_h = content_h * scale;

    std.debug.assert(scaled_w <= window_w);
    std.debug.assert(scaled_h <= window_h);

    const offset_x = (window_w - scaled_w) / 2;
    const offset_y = (window_h - scaled_h) / 2;

    std.debug.assert(2 * offset_x + scaled_w <= window_w);
    std.debug.assert(2 * offset_y + scaled_h <= window_h);

    var src_ptr: [*]const ashet.abi.Color = server.screen.backbuffer.ptr;
    var dst_ptr: [*]Pixel = pixels.ptr + window_w * offset_y + offset_x;

    for (0..content_h) |_| {
        for (0..scale) |_| {
            for (dst_ptr[0..scaled_w], 0..) |*pixel, x| {
                pixel.* = palette_lut[src_ptr[x / scale].to_u8()];
            }
            dst_ptr += server.window_width;
        }
        src_ptr += server.screen.width;
    }
}

fn onXdgSurfaceEvent(
    surface_configured: *bool,
    connection: shimizu.Connection,
    xdg_surface: xdg_shell.xdg_surface,
    event: xdg_shell.xdg_surface.Event,
) !void {
    switch (event) {
        .configure => |configure| {
            try xdg_surface.ack_configure(connection, configure.serial);
            surface_configured.* = true;
        },
    }
}

/// An ARGB framebuffer
pub const Framebuffers = struct {
    size: [2]u32,
    fd: std.posix.fd_t,
    memory: []align(std.heap.page_size_min) u8,

    wl_shm_pool: shimizu.Proxy(wayland.wl_shm_pool),
    buffers: std.BoundedArray(Buffer, 6),
    free: std.BoundedArray(u32, 6),

    wl_buffer_event_listener: shimizu.Listener,

    pub fn allocate(this: *@This(), wl_shm: shimizu.Proxy(wayland.wl_shm), size: [2]u32, count: u32) !void {
        std.debug.assert(count <= 6);
        const fd = try std.posix.memfd_create("framebuffers", 0);

        const frame_size = size[0] * size[1] * @sizeOf(Pixel);
        const total_size = frame_size * count;
        try std.posix.ftruncate(fd, total_size);

        const memory = try std.posix.mmap(null, total_size, std.posix.PROT.WRITE, .{ .TYPE = .SHARED }, fd, 0);

        const wl_shm_pool = try wl_shm.sendRequest(.create_pool, .{
            .fd = @enumFromInt(fd),
            .size = @intCast(total_size),
        });

        var buffers = std.BoundedArray(Buffer, 6){};
        var free = std.BoundedArray(u32, 6){};
        var offset: u32 = 0;
        for (0..count) |index| {
            const wl_buffer = try wl_shm_pool.sendRequest(.create_buffer, .{
                .offset = @intCast(offset),
                .width = @intCast(size[0]),
                .height = @intCast(size[1]),
                .stride = @intCast(size[0] * @sizeOf(Pixel)),
                .format = .bgr888,
            });
            buffers.appendAssumeCapacity(.{
                .wl_buffer = wl_buffer,
                .pixels = std.mem.bytesAsSlice(Pixel, memory[offset..][0..frame_size]),
            });
            free.appendAssumeCapacity(@intCast(index));
            offset += frame_size;
        }

        this.* = .{
            .size = size,
            .fd = fd,
            .memory = memory,
            .wl_shm_pool = wl_shm_pool,
            .buffers = buffers,
            .free = free,
            .wl_buffer_event_listener = undefined,
        };
        for (this.buffers.slice()) |buffer| {
            buffer.wl_buffer.setEventListener(&this.wl_buffer_event_listener, onWlBufferEvent, null);
        }
    }

    pub fn deinit(this: *@This()) void {
        this.wl_shm_pool.sendRequest(.destroy, .{}) catch {};
        std.posix.munmap(this.memory);
        std.posix.close(this.fd);
        this.* = undefined;
    }

    const Buffer = struct {
        wl_buffer: shimizu.Proxy(wayland.wl_buffer),
        pixels: []Pixel,
    };

    pub fn getBuffer(this: *@This()) !Buffer {
        const buffer_index = this.free.pop() orelse return error.OutOfFramebuffers;
        return this.buffers.slice()[buffer_index];
    }

    fn onWlBufferEvent(listener: *shimizu.Listener, wl_buffer: shimizu.Proxy(wayland.wl_buffer), event: wayland.wl_buffer.Event) !void {
        const this: *@This() = @fieldParentPtr("wl_buffer_event_listener", listener);
        switch (event) {
            .release => {
                const index = for (this.buffers.slice(), 0..) |buffer, i| {
                    if (buffer.wl_buffer.id == wl_buffer.id) break i;
                } else return;
                this.free.appendAssumeCapacity(@intCast(index));
            },
        }
    }
};

fn renderGradient(framebuffer: []Pixel, fb_size: [2]u32, frame_count: u32) void {
    for (0..fb_size[1]) |y| {
        const row = framebuffer[y * fb_size[0] .. (y + 1) * fb_size[0]];
        for (row, 0..fb_size[0]) |*pixel, x| {
            pixel.* = .{
                .r = @truncate(x +% frame_count),
                .g = @truncate(y +% frame_count),
                .b = 0x00,
                // .a = 0xFF,
            };
        }
    }
}

pub const Pixel = ashet.abi.Color.ARGB8888;

fn onXdgToplevelEvent(
    server: *Wayland_Display,
    connection: shimizu.Connection,
    xdg_toplevel: xdg_shell.xdg_toplevel,
    event: xdg_shell.xdg_toplevel.Event,
) !void {
    _ = xdg_toplevel;
    _ = connection;

    switch (event) {
        .close => server.running = false,
        .configure => |cfg| {
            if (cfg.width > 0) {
                server.window_width = @intCast(cfg.width);
            }
            if (cfg.height > 0) {
                server.window_height = @intCast(cfg.height);
            }
        },
        else => {},
    }
}

fn onXdgWmBaseEvent(
    _: void,
    connection: shimizu.Connection,
    xdg_wm_base: xdg_shell.xdg_wm_base,
    event: xdg_shell.xdg_wm_base.Event,
) !void {
    switch (event) {
        .ping => |ping| {
            try xdg_wm_base.pong(connection, ping.serial);
        },
    }
}

fn onWlCallbackSetTrue(
    bool_ptr: *bool,
    connection: shimizu.Connection,
    wl_callback: shimizu.core.wl_callback,
    event: shimizu.core.wl_callback.Event,
) !void {
    _ = connection;
    _ = wl_callback;
    _ = event;

    bool_ptr.* = true;
}

fn create_wayland_object(connection: shimizu.Connection, registry: wayland.wl_registry, global: wayland.wl_registry.Event.Global, comptime T: type) !T {
    const obj_id = try registry.bind(
        connection,
        global.name,
        T.NAME,
        T.VERSION,
    );
    return @enumFromInt(@intFromEnum(obj_id));
}

const Seat = struct {
    wl_seat: wayland.wl_seat,

    wl_pointer: ?wayland.wl_pointer = null,
    wl_keyboard: ?wayland.wl_keyboard = null,
};

fn onRegistryEvent(server: *Wayland_Display, connection: shimizu.Connection, registry: wayland.wl_registry, event: wayland.wl_registry.Event) !void {
    switch (event) {
        .global => |global| {
            if (shimizu.globalMatchesInterface(global, wayland.wl_compositor)) {
                server.wl_compositor = try create_wayland_object(
                    connection,
                    registry,
                    global,
                    wayland.wl_compositor,
                );
                server.has_wl_compositor = true;
            } else if (shimizu.globalMatchesInterface(global, xdg_shell.xdg_wm_base)) {
                server.xdg_wm_base = try create_wayland_object(
                    connection,
                    registry,
                    global,
                    xdg_shell.xdg_wm_base,
                );
                server.has_xdg_wm_base = true;
            } else if (shimizu.globalMatchesInterface(global, wayland.wl_shm)) {
                server.wl_shm = try create_wayland_object(
                    connection,
                    registry,
                    global,
                    wayland.wl_shm,
                );
                server.has_wl_shm = true;
            } else if (shimizu.globalMatchesInterface(global, wayland.wl_seat)) {
                if (server.seat != null) {
                    logger.warn("multiple seats detected; multiple seat handling not implemented.", .{});
                    return;
                }
                const wl_seat = try create_wayland_object(
                    connection,
                    registry,
                    global,
                    wayland.wl_seat,
                );
                server.seat = .{
                    .wl_seat = wl_seat,
                };
                try connection.setEventListener(server.seat.?.wl_seat, *Wayland_Display, onWlSeatEvent, server);
            } else if (shimizu.globalMatchesInterface(global, zxdg_decoration_manager_v1)) {
                server.xdg_decorations_manager = try create_wayland_object(
                    connection,
                    registry,
                    global,
                    zxdg_decoration_manager_v1,
                );
            }
        },

        else => {},
    }
}

fn onWlSeatEvent(server: *Wayland_Display, connection: shimizu.Connection, wl_seat: wayland.wl_seat, event: wayland.wl_seat.Event) !void {
    const seat = &server.seat.?;
    switch (event) {
        .capabilities => |capabilities| {
            if (capabilities.capabilities.keyboard) {
                logger.info("has keyboard", .{});
                if (seat.wl_keyboard == null) {
                    seat.wl_keyboard = try wl_seat.get_keyboard(connection);
                    try connection.setEventListener(seat.wl_keyboard.?, *Seat, onKeyboardCallback, seat);
                }
            } else {
                logger.info("has no more keyboard", .{});
                if (seat.wl_keyboard) |wl_keyboard| {
                    try wl_keyboard.release(connection);
                    seat.wl_keyboard = null;
                }
            }

            if (capabilities.capabilities.pointer) {
                logger.info("has pointer", .{});
                if (seat.wl_pointer == null) {
                    seat.wl_pointer = try wl_seat.get_pointer(connection);
                    try connection.setEventListener(seat.wl_pointer.?, *Wayland_Display, onPointerCallback, server);
                }
            } else {
                logger.info("has no more pointer", .{});
                if (seat.wl_pointer) |pointer_id| {
                    try pointer_id.release(connection);
                    seat.wl_pointer = null;
                }
            }
        },
        .name => {},
    }
}

fn onPointerCallback(server: *Wayland_Display, connection: shimizu.Connection, wl_pointer: wayland.wl_pointer, event: wayland.wl_pointer.Event) !void {
    _ = connection;
    _ = wl_pointer;
    switch (event) {
        .enter => |enter| {
            logger.debug("pointer.enter({})", .{enter});
        },
        .leave => |leave| {
            logger.debug("pointer.leave({})", .{leave});
        },
        .motion => |motion| {
            logger.debug("pointer.motion({})", .{motion});

            const scale: i24 = @intCast(server.get_content_scale());

            if (scale > 0) {
                ashet.input.push_raw_event(.{
                    .mouse_abs_motion = .{
                        .x = @intCast(@divFloor(motion.surface_x.integer, scale)),
                        .y = @intCast(@divFloor(motion.surface_y.integer, scale)),
                    },
                });
            }
        },
        .button => |button| blk: {
            logger.debug("pointer.button({})", .{button});

            const mouse_button: ashet.abi.MouseButton = evdev.mouseFromEvdev(button.button) orelse {
                logger.warn("unsupported mouse button: 0x{X:0>3}", .{button.button});
                break :blk;
            };

            ashet.input.push_raw_event(.{
                .mouse_button = .{
                    .button = mouse_button,
                    .down = (button.state == .pressed),
                },
            });
        },
        .axis => |axis| {
            logger.debug("pointer.axis({})", .{axis});

            switch (axis.axis) {
                .vertical_scroll => {
                    const button: ashet.abi.MouseButton = if (axis.value.integer < 0)
                        .wheel_down
                    else
                        .wheel_up;

                    ashet.input.push_raw_event(.{
                        .mouse_button = .{
                            .button = button,
                            .down = true,
                        },
                    });
                    ashet.input.push_raw_event(.{
                        .mouse_button = .{
                            .button = button,
                            .down = false,
                        },
                    });
                },

                else => {
                    logger.warn("unsupported mouse axis: {}", .{axis.axis});
                },
            }
        },
        else => {},
    }
}

fn onKeyboardCallback(seat: *Seat, connection: shimizu.Connection, wl_keyboard: wayland.wl_keyboard, event: wayland.wl_keyboard.Event) !void {
    _ = seat;
    _ = connection;
    _ = wl_keyboard;
    switch (event) {
        .keymap => |keymap_info| {
            defer std.posix.close(@intCast(@intFromEnum(keymap_info.fd)));
            logger.debug("keyboard.keymap({})", .{keymap_info});
        },

        .repeat_info => |repeat_info| {
            logger.debug("keyboard.repeat_info({})", .{repeat_info});
        },

        .modifiers => |m| {
            logger.debug("keyboard.modifiers({})", .{m});
        },
        .key => |k| {
            logger.debug("keyboard.key({})", .{k});

            if (evdev.keyFromEvdev(k.key)) |scancode| {
                ashet.input.push_raw_event(.{
                    .keyboard = .{
                        .usage = scancode,
                        .down = (k.state == .pressed),
                    },
                });
            } else {
                logger.err("received unknown scancode 0x{X:0>8}", .{k.key});
            }
        },
        else => {
            logger.warn("unhandled keyboard event {}", .{event});
        },
    }
}
