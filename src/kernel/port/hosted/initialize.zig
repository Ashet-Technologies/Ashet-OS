//!
//! This file implements the shared logic between all hosted implementations
//!

const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.hosted);

const sdl_enabled = false;

const args_parser = @import("args");

const VNC_Server = @import("VNC_Server.zig");
const SDL_Display = @import("SDL_Display.zig");

const network = @import("network");
const sdl = @import("SDL2.zig");

const hw = struct {
    //! list of fixed hardware components

    var systemClock: ashet.drivers.rtc.HostedSystemClock = .{};
};

const KernelOptions = struct {
    //
};

pub var kernel_options: KernelOptions = .{};

var startup_time: ?std.time.Instant = null;

pub fn get_tick_count_ms() u64 {
    if (startup_time) |sutime| {
        var now = std.time.Instant.now() catch unreachable;
        return @intCast(now.since(sutime) / std.time.ns_per_ms);
    } else {
        return 0;
    }
}

fn badKernelOption(option: []const u8, comptime reason: []const u8, args: anytype) noreturn {
    std.log.err("bad command line interface: component '{}': " ++ reason, .{std.zig.fmtEscapes(option)} ++ args);
    std.process.exit(1);
}

var global_memory_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
pub const global_memory = global_memory_arena.allocator();

pub const VideoDriverOptions = struct {
    video_out_index: usize,
    res_x: u16,
    res_y: u16,
};

pub const VideoDriverCtor = *const fn (VideoDriverOptions) anyerror!void;

pub fn initialize(comptime video_drivers: std.StaticStringMap(VideoDriverCtor)) !void {
    const shared_video_drivers: []const []const u8 = &.{
        "dummy",
        "vnc",
        "sdl",
    };

    comptime for (shared_video_drivers) |dri| {
        if (video_drivers.get(dri) != null)
            @compileError("duplicate video driver key: " ++ dri);
    };

    try network.init();

    if (sdl_enabled) {
        if (sdl.SDL_Init(sdl.SDL_INIT_EVERYTHING) < 0) {
            @panic("failed to init SDL");
        }
    }

    startup_time = try std.time.Instant.now();
    logger.debug("startup time = {?}", .{startup_time});

    ashet.drivers.install(&hw.systemClock.driver);

    var video_out_index: usize = 0;
    var any_sdl_output: bool = false;

    const cli = args_parser.parseForCurrentProcess(KernelOptions, global_memory, .print) catch std.process.exit(1);
    kernel_options = cli.options;

    for (cli.positionals) |arg| {
        var iter = std.mem.splitScalar(u8, arg, ';');
        const component = iter.next().?; // first element does always exist

        if (std.mem.eql(u8, component, "drive")) {
            // "drive:<image>:<rw|ro>"
            const disk_file = iter.next() orelse badKernelOption("drive", "missing file name", .{});

            const mode_str = iter.next() orelse "ro";
            const mode: std.fs.File.OpenMode = if (std.mem.eql(u8, mode_str, "ro"))
                std.fs.File.OpenMode.read_only
            else if (std.mem.eql(u8, mode_str, "rw"))
                std.fs.File.OpenMode.read_write
            else
                badKernelOption("drive", "bad mode '{s}'", .{mode_str});

            const file = try std.fs.cwd().openFile(disk_file, .{ .mode = mode });

            const driver = try global_memory.create(ashet.drivers.block.Host_Disk_Image);

            driver.* = try ashet.drivers.block.Host_Disk_Image.init(file, mode);

            ashet.drivers.install(&driver.driver);
        } else if (std.mem.eql(u8, component, "video")) {
            // "video:<type>:<width>:<height>:<args>"
            const device_type = iter.next() orelse badKernelOption("video", "missing video device type", .{});

            const res_x_str = iter.next() orelse badKernelOption("video", "missing horizontal resolution", .{});
            const res_y_str = iter.next() orelse badKernelOption("video", "missing vertical resolution", .{});

            const res_x = std.fmt.parseInt(u16, res_x_str, 10) catch badKernelOption("video", "bad horizontal resolution '{s}'", .{res_x_str});
            const res_y = std.fmt.parseInt(u16, res_y_str, 10) catch badKernelOption("video", "bad vertical resolution '{s}'", .{res_y_str});

            if (res_x == 0 or res_y == 0) badKernelOption("video", "resolution must be larger than zero", .{});

            if (std.mem.eql(u8, device_type, "vnc")) {
                // "video:vnc:<width>:<height>:<ip>:<port>"

                const address_str = iter.next() orelse badKernelOption("video", "missing vnc address", .{});
                const port_str = iter.next() orelse badKernelOption("video", "missing vnc port", .{});

                const address = network.Address.parse(address_str) catch badKernelOption("video", "bad vnc endpoint '{s}'", .{address_str});
                const port = std.fmt.parseInt(u16, port_str, 10) catch badKernelOption("video", "bad vnc endpoint '{s}'", .{port_str});

                const server = try VNC_Server.init(
                    global_memory,
                    .{ .address = address, .port = port },
                    res_x,
                    res_y,
                );

                // TODO: This has to be solved differently
                ashet.input.keyboard.model = &ashet.input.keyboard.models.vnc;

                ashet.drivers.install(&server.screen.driver);
            } else if (std.mem.eql(u8, device_type, "sdl")) {
                if (sdl_enabled) {
                    const display = try SDL_Display.init(
                        global_memory,
                        video_out_index,
                        res_x,
                        res_y,
                    );

                    ashet.drivers.install(&display.screen.driver);

                    any_sdl_output = true;
                } else {
                    badKernelOption("sdl", "sdl video output disabled!", .{});
                }
            } else if (std.mem.eql(u8, device_type, "dummy")) {
                if (res_x != 320 or res_y != 240) badKernelOption("video", "resolution must be 320x240!", .{});
                const driver = try global_memory.create(ashet.drivers.video.Virtual_Video_Output);
                driver.* = ashet.drivers.video.Virtual_Video_Output.init();
                ashet.drivers.install(&driver.driver);
            } else if (video_drivers.get(device_type)) |video_driver_ctor| {
                try video_driver_ctor(.{
                    .video_out_index = video_out_index,
                    .res_x = res_x,
                    .res_y = res_y,
                });
            } else {
                badKernelOption("video", "bad video device type '{s}'", .{device_type});
            }

            video_out_index += 1;
        } else {
            badKernelOption(component, "does not exist", .{});
        }
    }

    if (sdl_enabled) {
        if (any_sdl_output) {
            const thread = try ashet.scheduler.Thread.spawn(handle_SDL_events, null, .{});
            try thread.setName("sdl.eventloop");
            try thread.start();
            thread.detach();
        }
    }
}

pub fn debug_write(msg: []const u8) void {
    std.debug.print("{s}", .{msg});
}

var linear_memory: [64 * 1024 * 1024]u8 align(4096) = undefined;

pub fn get_linear_memory_region() ashet.memory.Range {
    return .{
        .base = @intFromPtr(&linear_memory),
        .length = linear_memory.len,
    };
}

fn display_from_sdl_window_id(id: u32) ?*SDL_Display {
    const window = sdl.SDL_GetWindowFromID(id) orelse return null;
    return SDL_Display.from_window(window);
}

fn handle_SDL_events(ptr: ?*anyopaque) callconv(.C) u32 {
    errdefer |err| {
        logger.err("SDL event loop crashed: {s}", .{@errorName(err)});
        std.os.exit(1);
    }
    _ = ptr;

    while (true) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => std.process.exit(1),

                sdl.SDL_MOUSEMOTION => {
                    if (display_from_sdl_window_id(event.motion.windowID)) |display| {
                        // TODO: Handle multiple video outputs

                        var raw_window_width: c_int = 0;
                        var raw_window_height: c_int = 0;

                        sdl.SDL_GetWindowSize(
                            display.window,
                            &raw_window_width,
                            &raw_window_height,
                        );

                        const window_width: i32 = @intCast(raw_window_width);
                        const window_height: i32 = @intCast(raw_window_height);

                        const screen_width: i32 = display.screen.width;
                        const screen_height: i32 = display.screen.height;

                        const window_x: i32 = event.motion.x;
                        const window_y: i32 = event.motion.y;

                        const screen_x: i32 = @divFloor((screen_width - 1) * window_x, window_width - 1);
                        const screen_y: i32 = @divFloor((screen_height - 1) * window_y, window_height - 1);

                        ashet.input.push_raw_event(.{ .mouse_abs_motion = .{
                            .x = @intCast(screen_x),
                            .y = @intCast(screen_y),
                        } });
                    }
                },

                sdl.SDL_MOUSEBUTTONDOWN, sdl.SDL_MOUSEBUTTONUP => blk: {
                    if (display_from_sdl_window_id(event.motion.windowID)) |display| {
                        _ = display;

                        ashet.input.push_raw_event(.{ .mouse_button = .{
                            .button = switch (event.button.button) {
                                sdl.SDL_BUTTON_LEFT => .left,
                                sdl.SDL_BUTTON_MIDDLE => .middle,
                                sdl.SDL_BUTTON_RIGHT => .right,
                                sdl.SDL_BUTTON_X1 => .nav_previous,
                                sdl.SDL_BUTTON_X2 => .nav_next,
                                else => break :blk,
                            },
                            .down = (event.button.state == sdl.SDL_PRESSED),
                        } });
                    }
                },

                else => {
                    logger.debug("unhandled SDL event of type {}", .{event.type});
                },
            }
        }

        ashet.scheduler.yield();
    }
}
