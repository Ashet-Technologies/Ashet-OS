//!
//! Hosted Linux PC
//!

const std = @import("std");
const ashet = @import("../../../main.zig");
const network = @import("network");
const vnc = @import("vnc");
const logger = std.log.scoped(.linux_pc);

const args = @import("args");

pub const machine_config = ashet.ports.MachineConfig{
    .load_sections = .{ .data = false, .bss = false },
};

const hw = struct {
    //! list of fixed hardware components

    var systemClock: ashet.drivers.rtc.HostedSystemClock = .{};
};

const KernelOptions = struct {
    //
};

var kernel_options: KernelOptions = .{};
var cli_ok: bool = true;

fn printCliError(err: args.Error) !void {
    logger.err("invalid cli argument: {}", .{err});
    cli_ok = false;
}

var startup_time: ?std.time.Instant = null;

pub fn get_tick_count() u64 {
    if (startup_time) |sutime| {
        var now = std.time.Instant.now() catch unreachable;
        return @intCast(now.since(sutime) / std.time.ns_per_us);
    } else {
        return 0;
    }
}

fn badKernelOption(option: []const u8, reason: []const u8) noreturn {
    std.log.err("bad command line interface: component '{}': {s}", .{ std.zig.fmtEscapes(option), reason });
    std.os.exit(1);
}

var global_memory_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const global_memory = global_memory_arena.allocator();

pub fn initialize() !void {
    try network.init();

    startup_time = try std.time.Instant.now();

    ashet.drivers.install(&hw.systemClock.driver);

    const argv = try std.process.argsAlloc(global_memory);

    for (argv[1..]) |arg| {
        var iter = std.mem.split(u8, arg, ":");
        const component = iter.next().?; // first element does always exist

        if (std.mem.eql(u8, component, "drive")) {
            // "drive:<image>:<rw|ro>"
            const disk_file = iter.next() orelse badKernelOption("drive", "missing file name");

            const mode_str = iter.next() orelse "ro";
            const mode: std.fs.File.OpenMode = if (std.mem.eql(u8, mode_str, "ro"))
                std.fs.File.OpenMode.read_only
            else if (std.mem.eql(u8, mode_str, "rw"))
                std.fs.File.OpenMode.read_write
            else
                badKernelOption("drive", "bad mode");

            const file = try std.fs.cwd().openFile(disk_file, .{ .mode = mode });

            const driver = try global_memory.create(ashet.drivers.block.Host_Disk_Image);

            driver.* = try ashet.drivers.block.Host_Disk_Image.init(file, mode);

            ashet.drivers.install(&driver.driver);
        } else if (std.mem.eql(u8, component, "video")) {
            // "video:<type>:<width>:<height>:<args>"
            const device_type = iter.next() orelse badKernelOption("video", "missing video device type");

            const res_x_str = iter.next() orelse badKernelOption("video", "missing horizontal resolution");
            const res_y_str = iter.next() orelse badKernelOption("video", "missing vertical resolution");

            const res_x = std.fmt.parseInt(u16, res_x_str, 10) catch badKernelOption("video", "bad horizontal resolution");
            const res_y = std.fmt.parseInt(u16, res_y_str, 10) catch badKernelOption("video", "bad vertical resolution");

            if (res_x == 0 or res_y == 0) badKernelOption("video", "resolution must be larger than zero");

            if (std.mem.eql(u8, device_type, "vnc")) {
                // "video:<type>:<width>:<height>:<ip>:<port>"

                const address_str = iter.next() orelse badKernelOption("video", "missing vnc address");
                const port_str = iter.next() orelse badKernelOption("video", "missing vnc port");

                const address = network.Address.parse(address_str) catch badKernelOption("video", "bad vnc endpoint");
                const port = std.fmt.parseInt(u16, port_str, 10) catch badKernelOption("video", "bad vnc endpoint");

                const server = try VNC_Server.init(
                    .{ .address = address, .port = port },
                    res_x,
                    res_y,
                );

                ashet.input.keyboard.model = &ashet.input.keyboard.models.vnc;

                ashet.drivers.install(&server.screen.driver);
            } else if (std.mem.eql(u8, device_type, "sdl")) {
                badKernelOption("video", "sdl not supported yet!");
            } else if (std.mem.eql(u8, device_type, "drm")) {
                badKernelOption("video", "drm not supported yet!");
            } else if (std.mem.eql(u8, device_type, "dummy")) {
                if (res_x != 320 or res_y != 240) badKernelOption("video", "resolution must be 320x240!");
                const driver = try global_memory.create(ashet.drivers.video.Virtual_Video_Output);
                driver.* = ashet.drivers.video.Virtual_Video_Output.init();
                ashet.drivers.install(&driver.driver);
            } else {
                badKernelOption("video", "bad video device type");
            }
        } else {
            badKernelOption(component, "does not exist");
        }
    }
}

pub fn debugWrite(msg: []const u8) void {
    std.debug.print("{s}", .{msg});
}

// extern const __machine_linmem_start: u8 align(4);
// extern const __machine_linmem_end: u8 align(4);

comptime {
    // Provide some global symbols.
    // We can fake the {flash,data,bss}_{start,end} symbols,
    // as we know that these won't overlap with linmem anyways:
    asm (
        \\
        \\.global kernel_stack_start
        \\.global kernel_stack
        \\kernel_stack_start:
        \\.space 8 * 1024 * 1024        # 8 MB of stack
        \\kernel_stack:
        \\
        \\__kernel_flash_start:
        \\__kernel_flash_end:
        \\__kernel_data_start:
        \\__kernel_data_end:
        \\__kernel_bss_start:
        \\__kernel_bss_end:
    );
}

var linear_memory: [64 * 1024 * 1024]u8 align(4096) = undefined;

pub fn getLinearMemoryRegion() ashet.memory.Section {
    return ashet.memory.Section{
        .offset = @intFromPtr(&linear_memory),
        .length = linear_memory.len,
    };
}

const VNC_Server = struct {
    socket: network.Socket,

    screen: ashet.drivers.video.Host_VNC_Output,
    input: ashet.drivers.input.Host_VNC_Input,

    pub fn init(
        endpoint: network.EndPoint,
        width: u16,
        height: u16,
    ) !*VNC_Server {
        var server_sock = try network.Socket.create(.ipv4, .tcp);
        errdefer server_sock.close();

        try server_sock.enablePortReuse(true);
        try server_sock.bind(endpoint);

        try server_sock.listen();

        const server = try global_memory.create(VNC_Server);
        errdefer global_memory.destroy(server);

        server.* = .{
            .socket = server_sock,
            .screen = try ashet.drivers.video.Host_VNC_Output.init(width, height),
            .input = ashet.drivers.input.Host_VNC_Input.init(),
        };

        const thread = try std.Thread.spawn(.{}, handler, .{server});
        thread.detach();

        return server;
    }

    fn handler(vd: *VNC_Server) !void {
        while (true) {
            const client = try vd.socket.accept();

            var server = try vnc.Server.open(std.heap.page_allocator, client, .{
                .screen_width = vd.screen.width,
                .screen_height = vd.screen.height,
                .desktop_name = "Ashet OS",
            });
            defer server.close();

            std.debug.print("protocol version:  {}\n", .{server.protocol_version});
            std.debug.print("shared connection: {}\n", .{server.shared_connection});

            const Point = struct { x: u16, y: u16 };
            var old_mouse: ?Point = null;
            var old_button: u8 = 0;

            while (try server.waitEvent()) |event| {
                switch (event) {
                    .set_pixel_format => {}, // use internal handler

                    .framebuffer_update_request => |in_req| {
                        const req: vnc.ClientEvent.FramebufferUpdateRequest = .{
                            .incremental = false,
                            .x = 0,
                            .y = 0,
                            .width = vd.screen.width,
                            .height = vd.screen.height,
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

                                const color = if (px < vd.screen.width and py < vd.screen.height) blk: {
                                    const offset = py * vd.screen.width + px;
                                    std.debug.assert(offset < vd.screen.backbuffer.len);

                                    const index = vd.screen.backbuffer[offset];

                                    const raw_color = vd.screen.palette[@intFromEnum(index)];

                                    const rgb = raw_color.toRgb888();

                                    break :blk vnc.Color{
                                        .r = @as(f32, @floatFromInt(rgb.r)) / 255.0,
                                        .g = @as(f32, @floatFromInt(rgb.g)) / 255.0,
                                        .b = @as(f32, @floatFromInt(rgb.b)) / 255.0,
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
                        var cs = ashet.CriticalSection.enter();
                        defer cs.leave();
                        ashet.input.pushRawEventFromIRQ(.{
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
                                ashet.input.pushRawEventFromIRQ(.{
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
                                    ashet.input.pushRawEventFromIRQ(.{
                                        .mouse_button = .{
                                            .button = switch (i) {
                                                0 => .left,
                                                1 => .right,
                                                2 => .middle,
                                                3 => .nav_previous,
                                                4 => .nav_next,
                                                5 => .wheel_down,
                                                6 => .wheel_up,
                                                else => unreachable,
                                            },
                                            .down = (ptr.buttons & mask) != 0,
                                        },
                                    });
                                }
                            }
                            old_button = ptr.buttons;
                        }
                    },

                    else => std.debug.print("received unhandled event: {}\n", .{event}),
                }
            }
        }
    }
};
