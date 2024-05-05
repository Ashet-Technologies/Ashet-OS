const std = @import("std");
const ashet = @import("../../main.zig");
const network = @import("network");
const vnc = @import("vnc");
const logger = std.log.scoped(.virtual_screen);

const Host_VNC_Output = @This();
const Driver = ashet.drivers.Driver;
const ColorIndex = ashet.abi.ColorIndex;
const Color = ashet.abi.Color;
const Resolution = ashet.abi.Size;

socket: network.Socket,

backbuffer: []align(ashet.memory.page_size) ColorIndex,
width: u16,
height: u16,

palette: [256]Color = ashet.video.defaults.palette,

driver: Driver = .{
    .name = "Host VNC Screen",
    .class = .{
        .video = .{
            .getVideoMemoryFn = getVideoMemory,
            .getPaletteMemoryFn = getPaletteMemory,
            .setBorderFn = setBorder,
            .flushFn = flush,
            .getResolutionFn = getResolution,
            .getMaxResolutionFn = getMaxResolution,
            .getBorderFn = getBorder,
            .setResolutionFn = setResolution,
        },
    },
},

pub fn init(
    vd: *Host_VNC_Output,
    endpoint: network.EndPoint,
    width: u16,
    height: u16,
) !void {
    const fb = try std.heap.page_allocator.alignedAlloc(
        ColorIndex,
        ashet.memory.page_size,
        @as(u32, width) * @as(u32, height),
    );
    errdefer std.heap.page_allocator.free(fb);

    var server_sock = try network.Socket.create(.ipv4, .tcp);
    errdefer server_sock.close();

    try server_sock.enablePortReuse(true);
    try server_sock.bind(endpoint);

    try server_sock.listen();

    vd.* = .{
        .socket = server_sock,
        .width = width,
        .height = height,
        .backbuffer = fb,
    };

    const thread = try std.Thread.spawn(.{}, server_handler, .{vd});
    thread.detach();
}

fn getVideoMemory(driver: *Driver) []align(ashet.memory.page_size) ColorIndex {
    const vd = @fieldParentPtr(Host_VNC_Output, "driver", driver);
    return vd.backbuffer;
}

fn getPaletteMemory(driver: *Driver) *[256]Color {
    const vd = @fieldParentPtr(Host_VNC_Output, "driver", driver);
    return &vd.palette;
}

fn getResolution(driver: *Driver) Resolution {
    const vd = @fieldParentPtr(Host_VNC_Output, "driver", driver);
    return Resolution{
        .width = vd.width,
        .height = vd.height,
    };
}

fn getMaxResolution(driver: *Driver) Resolution {
    const vd = @fieldParentPtr(Host_VNC_Output, "driver", driver);
    return Resolution{
        .width = vd.width,
        .height = vd.height,
    };
}

fn setResolution(driver: *Driver, width: u15, height: u15) void {
    const vd = @fieldParentPtr(Host_VNC_Output, "driver", driver);
    _ = vd;
    _ = width;
    _ = height;
    logger.warn("resize not supported of vnc screen!", .{});
}

fn setBorder(driver: *Driver, color: ColorIndex) void {
    const vd = @fieldParentPtr(Host_VNC_Output, "driver", driver);
    _ = vd;
    _ = color;
}

fn getBorder(driver: *Driver) ColorIndex {
    const vd = @fieldParentPtr(Host_VNC_Output, "driver", driver);
    _ = vd;
    return ColorIndex.get(0);
}

fn flush(driver: *Driver) void {
    const vd = @fieldParentPtr(Host_VNC_Output, "driver", driver);
    _ = vd;
}

fn server_handler(vd: *Host_VNC_Output) !void {
    while (true) {
        const client = try vd.socket.accept();

        var server = try vnc.Server.open(std.heap.page_allocator, client, .{
            .screen_width = vd.width,
            .screen_height = vd.height,
            .desktop_name = "Ashet OS",
        });
        defer server.close();

        std.debug.print("protocol version:  {}\n", .{server.protocol_version});
        std.debug.print("shared connection: {}\n", .{server.shared_connection});

        while (try server.waitEvent()) |event| {
            switch (event) {
                .set_pixel_format => {}, // use internal handler

                .framebuffer_update_request => |in_req| {
                    const req: vnc.ClientEvent.FramebufferUpdateRequest = .{
                        .incremental = false,
                        .x = 0,
                        .y = 0,
                        .width = vd.width,
                        .height = vd.height,
                    };
                    _ = in_req;

                    var fb = std.ArrayList(u8).init(std.heap.page_allocator);
                    defer fb.deinit();

                    var y: usize = 0;
                    while (y < req.height) : (y += 1) {
                        var x: usize = 0;
                        while (x < req.width) : (x += 1) {
                            const px = x + req.x;
                            const py = y + req.y;

                            const color = if (px < vd.width and py < vd.height) blk: {
                                const offset = py * vd.width + px;
                                std.debug.assert(offset < vd.backbuffer.len);

                                const index = vd.backbuffer[offset];

                                const raw_color = vd.palette[@intFromEnum(index)];

                                break :blk vnc.Color{
                                    .r = @as(f32, @floatFromInt(raw_color.r)) / 255.0,
                                    .g = @as(f32, @floatFromInt(raw_color.g)) / 255.0,
                                    .b = @as(f32, @floatFromInt(raw_color.b)) / 255.0,
                                };
                            } else vnc.Color{ .r = 1.0, .g = 0.0, .b = 1.0 };

                            var buf: [8]u8 = undefined;
                            const bits = server.pixel_format.encode(&buf, color);
                            try fb.appendSlice(bits);
                        }
                    }

                    try server.sendFramebufferUpdate(&[_]vnc.UpdateRectangle{
                        .{
                            .x = req.x,
                            .y = req.y,
                            .width = req.width,
                            .height = req.height,
                            .encoding = .raw,
                            .data = fb.items,
                        },
                    });
                },

                .key_event => |ev| {
                    if (ev.key == @as(vnc.Key, @enumFromInt(' '))) {
                        try server.sendBell();
                    } else if (ev.key == .@"return") {
                        try server.sendServerCutText("HELLO, WORLD!");
                    }
                },

                else => std.debug.print("received unhandled event: {}\n", .{event}),
            }
        }
    }
}
