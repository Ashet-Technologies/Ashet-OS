const std = @import("std");
const builtin = @import("builtin");
const network = @import("network");
const vnc = @import("vnc");
const logger = std.log.scoped(.host_vnc_server);

const ashet = @import("../../main.zig");

const VNC_Server = @This();

allocator: std.mem.Allocator,
socket: network.Socket,

screen: ashet.drivers.video.Host_VNC_Output,
input: ashet.drivers.input.Host_VNC_Input,

pub fn init(
    allocator: std.mem.Allocator,
    endpoint: network.EndPoint,
    width: u16,
    height: u16,
) !*VNC_Server {
    var server_sock = try network.Socket.create(.ipv4, .tcp);
    errdefer server_sock.close();

    try server_sock.enablePortReuse(true);
    try server_sock.bind(endpoint);

    try server_sock.listen();

    logger.info("Host Screen VNC Server available at {!}", .{
        server_sock.getLocalEndPoint(),
    });

    const server = try allocator.create(VNC_Server);
    errdefer allocator.destroy(server);

    server.* = .{
        .allocator = allocator,
        .socket = server_sock,
        .screen = try ashet.drivers.video.Host_VNC_Output.init(width, height),
        .input = ashet.drivers.input.Host_VNC_Input.init(),
    };

    const accept_thread = try std.Thread.spawn(.{}, connection_handler, .{server});
    accept_thread.detach();

    return server;
}

fn connection_handler(vd: *VNC_Server) !void {
    if (builtin.single_threaded)
        @compileError("Cannot use VNC_Server in single-threaded environment!");

    while (true) {
        var local_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer local_arena.deinit();

        const local_allocator = local_arena.allocator();

        const client = try vd.socket.accept();

        var server = try vnc.Server.open(std.heap.page_allocator, client, .{
            .screen_width = vd.screen.width,
            .screen_height = vd.screen.height,
            .desktop_name = "Ashet OS",
        });
        defer server.close();

        const new_framebuffer = try local_allocator.dupe(ashet.abi.Color, vd.screen.backbuffer);
        defer local_allocator.free(new_framebuffer);

        const old_framebuffer = try local_allocator.dupe(ashet.abi.Color, vd.screen.backbuffer);
        defer local_allocator.free(old_framebuffer);

        std.debug.print("protocol version:  {}\n", .{server.protocol_version});
        std.debug.print("shared connection: {}\n", .{server.shared_connection});

        const Point = struct { x: u16, y: u16 };
        var old_mouse: ?Point = null;
        var old_button: u8 = 0;

        var request_arena = std.heap.ArenaAllocator.init(local_allocator);
        defer request_arena.deinit();

        while (try server.waitEvent()) |event| {
            _ = request_arena.reset(.retain_capacity);
            const request_allocator = request_arena.allocator();

            switch (event) {
                .set_pixel_format => |pf| {
                    logger.info("change pixel format to {}", .{pf});
                }, // use internal handler

                .framebuffer_update_request => |req| {
                    {
                        // vd.screen.backbuffer_lock.lock();
                        // defer vd.screen.backbuffer_lock.unlock();
                        @memcpy(new_framebuffer, vd.screen.backbuffer);
                    }

                    // logger.info("framebuffer update request: {}", .{in_req});

                    var rectangles = std.ArrayList(vnc.UpdateRectangle).init(request_allocator);
                    defer rectangles.deinit();

                    const incremental_support = true;

                    if (incremental_support and req.incremental) {

                        // Compute differential update:
                        var base: usize = req.y * vd.screen.width;
                        var y: usize = 0;
                        while (y < req.height) : (y += 1) {
                            const old_scanline = old_framebuffer[base + req.x ..][0..req.width];
                            const new_scanline = new_framebuffer[base + req.x ..][0..req.width];

                            var first_diff: usize = old_scanline.len;
                            var last_diff: usize = 0;
                            for (old_scanline, new_scanline, 0..) |old, new, index| {
                                if (old.eql(new)) {
                                    first_diff = @min(first_diff, index);
                                    last_diff = @max(last_diff, index);
                                }
                            }

                            if (first_diff <= last_diff) {
                                try rectangles.append(try vd.encode_screen_rect(
                                    request_allocator,
                                    .{
                                        .x = @intCast(req.x + first_diff),
                                        .y = @intCast(req.y + y),
                                        .width = @intCast(last_diff - first_diff + 1),
                                        .height = 1,
                                    },
                                    new_framebuffer,
                                    server.pixel_format,
                                ));
                                // logger.debug("sending incremental update on scanline {} from {}...{}", .{
                                //     req.y + y,
                                //     req.x + first_diff,
                                //     last_diff,
                                // });
                            }

                            base += vd.screen.width;
                        }
                    } else {
                        // Simple full screen update:
                        try rectangles.append(try vd.encode_screen_rect(
                            request_allocator,
                            .{
                                .x = req.x,
                                .y = req.y,
                                .width = req.width,
                                .height = req.height,
                            },
                            new_framebuffer,
                            server.pixel_format,
                        ));
                    }

                    if (rectangles.items.len == 0) {
                        try rectangles.append(try vd.encode_screen_rect(
                            request_allocator,
                            .{
                                .x = req.x,
                                .y = req.y,
                                .width = 1,
                                .height = 1,
                            },
                            new_framebuffer,
                            server.pixel_format,
                        ));
                    }

                    // logger.debug("Respond to update request ({},{})+({}x{}) with {} updated rectangles", .{
                    //     req.x,                req.y, req.width, req.height,
                    //     rectangles.items.len,
                    // });
                    try server.sendFramebufferUpdate(rectangles.items);

                    @memcpy(old_framebuffer, new_framebuffer);
                },

                .key_event => |ev| {
                    var cs = ashet.CriticalSection.enter();
                    defer cs.leave();
                    ashet.input.push_raw_event_from_irq(.{
                        .keyboard = .{
                            .down = ev.down,
                            .scancode = @truncate(@intFromEnum(ev.key)),
                        },
                    });
                },

                .pointer_event => |ptr| {
                    var cs = ashet.CriticalSection.enter();
                    defer cs.leave();

                    if (old_mouse) |prev| {
                        if (prev.x != ptr.x or prev.y != ptr.y) {
                            ashet.input.push_raw_event_from_irq(.{
                                .mouse_abs_motion = .{
                                    .x = @intCast(ptr.x),
                                    .y = @intCast(ptr.y),
                                },
                            });
                        }
                    }
                    old_mouse = Point{
                        .x = ptr.x,
                        .y = ptr.y,
                    };

                    if (old_button != ptr.buttons) {
                        for (0..7) |i| {
                            const mask: u8 = @as(u8, 1) << @truncate(i);

                            if ((old_button ^ ptr.buttons) & mask != 0) {
                                ashet.input.push_raw_event_from_irq(.{
                                    .mouse_button = .{
                                        .button = switch (i) {
                                            0 => .left,
                                            1 => .middle,
                                            2 => .right,
                                            3 => .wheel_up,
                                            4 => .wheel_down,
                                            5 => .nav_previous,
                                            6 => .nav_next,
                                            else => std.debug.panic("unsupported VNC mouse button: {}", .{i}),
                                        },
                                        .down = (ptr.buttons & mask) != 0,
                                    },
                                });
                            }
                        }
                        old_button = ptr.buttons;
                    }
                },

                else => logger.warn("received unhandled event: {}", .{event}),
            }
        }
    }
}

fn encode_screen_rect(
    vd: VNC_Server,
    allocator: std.mem.Allocator,
    rect: struct { x: u16, y: u16, width: u16, height: u16 },
    framebuffer: []const ashet.abi.Color,
    pixel_format: vnc.PixelFormat,
) !vnc.UpdateRectangle {
    var fb = std.ArrayList(u8).init(allocator);
    defer fb.deinit();

    var y: usize = 0;
    while (y < rect.height) : (y += 1) {
        var x: usize = 0;
        while (x < rect.width) : (x += 1) {
            const px = x + rect.x;
            const py = y + rect.y;

            const color = if (px < vd.screen.width and py < vd.screen.height) blk: {
                const offset = py * vd.screen.width + px;
                std.debug.assert(offset < framebuffer.len);

                const color_8 = framebuffer[offset];

                const rgb = color_8.to_rgb888();

                break :blk vnc.Color{
                    .r = @as(f32, @floatFromInt(rgb.r)) / 255.0,
                    .g = @as(f32, @floatFromInt(rgb.g)) / 255.0,
                    .b = @as(f32, @floatFromInt(rgb.b)) / 255.0,
                };
            } else vnc.Color{ .r = 1.0, .g = 0.0, .b = 1.0 };

            var buf: [8]u8 = undefined;
            const bits = pixel_format.encode(&buf, color);
            try fb.appendSlice(bits);
        }
    }

    return .{
        .x = rect.x,
        .y = rect.y,
        .width = rect.width,
        .height = rect.height,
        .encoding = .raw,
        .data = try fb.toOwnedSlice(),
    };
}
