const std = @import("std");
const shimizu = @import("shimizu");
const wp = @import("wayland-protocols");

const ashet = @import("../../../main.zig");

const logger = std.log.scoped(.wayland_display);
const xdg_shell = wp.xdg_shell;

const Wayland_Display = @This();

allocator: std.mem.Allocator,
index: usize,

connection: shimizu.Connection,

wl_surface: shimizu.Proxy(shimizu.core.wl_surface),

xdg_surface: shimizu.Proxy(xdg_shell.xdg_surface),
xdg_toplevel: shimizu.Proxy(xdg_shell.xdg_toplevel),

wl_compositor: shimizu.Proxy(shimizu.core.wl_compositor),
xdg_wm_base: shimizu.Proxy(xdg_shell.xdg_wm_base),
wl_shm: shimizu.Proxy(shimizu.core.wl_shm),

globals: Globals = .{
    .wl_shm = null,
    .wl_compositor = null,
    .xdg_wm_base = null,
},

// allocate a some framebuffers for rendering to
framebuffers: Framebuffers,

// state to keep track of while rendering
frame_count: u32 = 0,
should_render: bool = true,
running: bool = true,

// event listeners
xdg_toplevel_listener: shimizu.Listener,
frame_callback_listener: shimizu.Listener,
xdg_wm_base_ping_listener: shimizu.Listener,
xdg_surface_listener: shimizu.Listener,

// devices:
screen: ashet.drivers.video.Host_VNC_Output,
// input: ashet.drivers.input.Host_SDL_Input,

pub fn init(
    allocator: std.mem.Allocator,
    index: usize,
    width: u16,
    height: u16,
) !*Wayland_Display {
    const server = try allocator.create(Wayland_Display);
    errdefer allocator.destroy(server);

    server.* = .{
        .allocator = allocator,
        .index = index,

        .screen = try .init(width, height),
        // .input = ashet.drivers.input.Host_SDL_Input.init(),

        .connection = undefined,
        .wl_surface = undefined,
        .xdg_surface = undefined,
        .xdg_toplevel = undefined,
        .wl_compositor = undefined,
        .xdg_wm_base = undefined,
        .wl_shm = undefined,

        .framebuffers = undefined,
        .xdg_toplevel_listener = undefined,
        .frame_callback_listener = undefined,
        .xdg_wm_base_ping_listener = undefined,
        .xdg_surface_listener = undefined,
    };

    @memset(server.screen.frontbuffer, ashet.abi.Color.blue);
    @memset(server.screen.backbuffer, ashet.abi.Color.red);

    server.connection = try shimizu.openConnection(allocator, .{});
    errdefer server.connection.close();

    const display = server.connection.getDisplayProxy();
    const registry = try display.sendRequest(.get_registry, .{});
    const registry_done_callback = try display.sendRequest(.sync, .{});

    registry.setEventListener(&server.globals.listener, Globals.onRegistryEvent, null);

    var registration_done = false;
    var registration_done_listener: shimizu.Listener = undefined;
    registry_done_callback.setEventListener(&registration_done_listener, onWlCallbackSetTrue, &registration_done);

    while (!registration_done) {
        try server.connection.recv();
    }

    server.wl_compositor = .{
        .connection = &server.connection,
        .id = server.globals.wl_compositor orelse return error.WlCompositorNotFound,
    };
    server.xdg_wm_base = .{
        .connection = &server.connection,
        .id = server.globals.xdg_wm_base orelse return error.XdgWmBaseNotFound,
    };
    server.wl_shm = .{
        .connection = &server.connection,
        .id = server.globals.wl_shm orelse return error.WlShmNotFound,
    };

    // set up a xdg_wm_base listener for the ping event

    server.xdg_wm_base.setEventListener(&server.xdg_wm_base_ping_listener, onXdgWmBaseEvent, null);

    server.wl_surface = try server.wl_compositor.sendRequest(.create_surface, .{});
    server.xdg_surface = try server.xdg_wm_base.sendRequest(.get_xdg_surface, .{ .surface = server.wl_surface.id });
    server.xdg_toplevel = try server.xdg_surface.sendRequest(.get_toplevel, .{});

    try server.wl_surface.sendRequest(.commit, .{});

    var surface_configured = false;

    server.xdg_surface.setEventListener(&server.xdg_surface_listener, onXdgSurfaceEvent, &surface_configured);

    while (!surface_configured) {
        try server.connection.recv();
    }

    try server.framebuffers.allocate(server.wl_shm, .{ 640, 480 }, 3);
    errdefer server.framebuffers.deinit();

    server.xdg_toplevel.setEventListener(&server.xdg_toplevel_listener, onXdgToplevelEvent, &server.running);

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
            // logger.info("swap", .{});
            const framebuffer = try server.framebuffers.getBuffer();

            // put some interesting colors into the framebuffer

            // renderGradient(framebuffer.pixels, server.framebuffers.size, server.frame_count);

            server.copyFromDriver(server.framebuffers.size, framebuffer.pixels);

            const frame_callback = try server.wl_surface.sendRequest(.frame, .{});
            frame_callback.setEventListener(&server.frame_callback_listener, onWlCallbackSetTrue, &server.should_render);

            try server.wl_surface.sendRequest(.attach, .{ .buffer = framebuffer.wl_buffer.id, .x = 0, .y = 0 });
            try server.wl_surface.sendRequest(.damage, .{ .x = 0, .y = 0, .width = std.math.maxInt(i32), .height = std.math.maxInt(i32) });
            try server.wl_surface.sendRequest(.commit, .{});

            server.should_render = false;
            server.frame_count += 1;
        }

        // logger.info("tick  {}", .{server.frame_count});
        try server.connection.recv();

        ashet.scheduler.yield();
    }
    logger.err("window closed, stopping simulation!", .{});
    std.process.exit(1);
}

fn copyFromDriver(server: *Wayland_Display, dst_size: [2]u32, pixels: []Pixel) void {
    const copy_w = @min(dst_size[0], server.screen.width);
    const copy_h = @min(dst_size[1], server.screen.height);

    var src_ptr: [*]const ashet.abi.Color = server.screen.backbuffer.ptr;
    var dst_ptr: [*]Pixel = pixels.ptr;

    for (0..copy_h) |_| {
        const src_row = src_ptr[0..copy_w];
        const dst_row = dst_ptr[0..copy_w];

        for (dst_row, src_row) |*d, s| {
            d.* = s.to_rgb888();
        }

        src_ptr += server.screen.width;
        dst_ptr += dst_size[0];
    }
}

fn onXdgSurfaceEvent(listener: *shimizu.Listener, xdg_surface: shimizu.Proxy(xdg_shell.xdg_surface), event: xdg_shell.xdg_surface.Event) shimizu.Listener.Error!void {
    const surface_configured: *bool = @ptrCast((listener.userdata.?));

    switch (event) {
        .configure => |configure| {
            try xdg_surface.sendRequest(.ack_configure, .{ .serial = configure.serial });
            surface_configured.* = true;
        },
    }
}

/// An ARGB framebuffer
pub const Framebuffers = struct {
    size: [2]u32,
    fd: std.posix.fd_t,
    memory: []align(std.heap.page_size_min) u8,

    wl_shm_pool: shimizu.Proxy(shimizu.core.wl_shm_pool),
    buffers: std.BoundedArray(Buffer, 6),
    free: std.BoundedArray(u32, 6),

    wl_buffer_event_listener: shimizu.Listener,

    pub fn allocate(this: *@This(), wl_shm: shimizu.Proxy(shimizu.core.wl_shm), size: [2]u32, count: u32) !void {
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
        wl_buffer: shimizu.Proxy(shimizu.core.wl_buffer),
        pixels: []Pixel,
    };

    pub fn getBuffer(this: *@This()) !Buffer {
        const buffer_index = this.free.pop() orelse return error.OutOfFramebuffers;
        return this.buffers.slice()[buffer_index];
    }

    fn onWlBufferEvent(listener: *shimizu.Listener, wl_buffer: shimizu.Proxy(shimizu.core.wl_buffer), event: shimizu.core.wl_buffer.Event) !void {
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

pub const Pixel = ashet.abi.Color.RGB888; //  = extern struct { r: u8, g: u8, b: u8, a: u8 };

fn onXdgToplevelEvent(listener: *shimizu.Listener, xdg_toplevel: shimizu.Proxy(xdg_shell.xdg_toplevel), event: xdg_shell.xdg_toplevel.Event) shimizu.Listener.Error!void {
    _ = xdg_toplevel;

    const running: *bool = @ptrCast((listener.userdata.?));

    switch (event) {
        .close => running.* = false,
        else => {},
    }
}

fn onXdgWmBaseEvent(listener: *shimizu.Listener, xdg_wm_base: shimizu.Proxy(xdg_shell.xdg_wm_base), event: xdg_shell.xdg_wm_base.Event) shimizu.Listener.Error!void {
    _ = listener;
    switch (event) {
        .ping => |ping| {
            try xdg_wm_base.sendRequest(.pong, .{ .serial = ping.serial });
        },
    }
}

fn onWlCallbackSetTrue(listener: *shimizu.Listener, wl_callback: shimizu.Proxy(shimizu.core.wl_callback), event: shimizu.core.wl_callback.Event) shimizu.Listener.Error!void {
    _ = wl_callback;
    _ = event;

    const bool_ptr: *bool = @ptrCast((listener.userdata.?));
    bool_ptr.* = true;
}

const Globals = struct {
    listener: shimizu.Listener = undefined,
    wl_shm: ?shimizu.Object.WithInterface(shimizu.core.wl_shm),
    wl_compositor: ?shimizu.Object.WithInterface(shimizu.core.wl_compositor),
    xdg_wm_base: ?shimizu.Object.WithInterface(xdg_shell.xdg_wm_base),

    fn onRegistryEvent(listener: *shimizu.Listener, registry: shimizu.Proxy(shimizu.core.wl_registry), event: shimizu.core.wl_registry.Event) shimizu.Listener.Error!void {
        const globals: *@This() = @fieldParentPtr("listener", listener);
        switch (event) {
            .global => |global| {
                if (shimizu.globalMatchesInterface(global, shimizu.core.wl_compositor)) {
                    const wl_compositor = try registry.connection.createObject(shimizu.core.wl_compositor);
                    try registry.sendRequest(.bind, .{ .name = global.name, .id = wl_compositor.id.asGenericNewId() });
                    globals.wl_compositor = wl_compositor.id;
                } else if (shimizu.globalMatchesInterface(global, xdg_shell.xdg_wm_base)) {
                    const xdg_wm_base = try registry.connection.createObject(xdg_shell.xdg_wm_base);
                    try registry.sendRequest(.bind, .{ .name = global.name, .id = xdg_wm_base.id.asGenericNewId() });
                    globals.xdg_wm_base = xdg_wm_base.id;
                } else if (shimizu.globalMatchesInterface(global, shimizu.core.wl_shm)) {
                    const wl_shm = try registry.connection.createObject(shimizu.core.wl_shm);
                    try registry.sendRequest(.bind, .{ .name = global.name, .id = wl_shm.id.asGenericNewId() });
                    globals.wl_shm = wl_shm.id;
                }
            },
            else => {},
        }
    }
};
