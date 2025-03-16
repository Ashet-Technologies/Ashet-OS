//!
//! Hosted Linux PC
//!

const std = @import("std");
const ashet = @import("../../../main.zig");
const network = @import("network");
const args_parser = @import("args");
const sdl = @import("SDL2.zig");
const logger = std.log.scoped(.linux_pc);

const VNC_Server = @import("VNC_Server.zig");
const SDL_Display = @import("SDL_Display.zig");
const Wayland_Display = @import("Wayland_Display.zig");

const sdl_enabled = false;

const mprotect = @import("mprotect.zig");

pub const machine_config = ashet.ports.MachineConfig{
    .load_sections = .{ .data = false, .bss = false },
    .memory_protection = .{
        .initialize = mprotect.initialize,
        .update = mprotect.update,
        .activate = mprotect.activate,
        .get_protection = mprotect.get_protection,
        .get_info = mprotect.query_address,
    },
    .initialize = initialize,
    .early_initialize = null,
    .debug_write = debug_write,
    .get_linear_memory_region = get_linear_memory_region,
    .get_tick_count_ms = get_tick_count_ms,
};

const hw = struct {
    //! list of fixed hardware components

    var systemClock: ashet.drivers.rtc.HostedSystemClock = .{};
};

const KernelOptions = struct {
    //
};

var kernel_options: KernelOptions = .{};

var startup_time: ?std.time.Instant = null;

fn get_tick_count_ms() u64 {
    if (startup_time) |sutime| {
        var now = std.time.Instant.now() catch unreachable;
        return @intCast(now.since(sutime) / std.time.ns_per_ms);
    } else {
        return 0;
    }
}

fn badKernelOption(option: []const u8, reason: []const u8) noreturn {
    std.log.err("bad command line interface: component '{}': {s}", .{ std.zig.fmtEscapes(option), reason });
    std.process.exit(1);
}

var global_memory_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
pub const global_memory = global_memory_arena.allocator();

fn initialize() !void {
    if (sdl_enabled) {
        if (sdl.SDL_Init(sdl.SDL_INIT_EVERYTHING) < 0) {
            @panic("failed to init SDL");
        }
    }

    const res = std.os.linux.mprotect(
        &linear_memory,
        linear_memory.len,
        std.os.linux.PROT.EXEC | std.os.linux.PROT.READ | std.os.linux.PROT.WRITE,
    );
    if (res != 0) @panic("mprotect failed!");

    try network.init();

    startup_time = try std.time.Instant.now();
    logger.debug("startup time = {?}", .{startup_time});

    ashet.drivers.install(&hw.systemClock.driver);

    var video_out_index: usize = 0;
    var any_sdl_output: bool = false;
    var any_wayland_output: bool = false;

    var cli = args_parser.parseForCurrentProcess(KernelOptions, global_memory, .print) catch std.process.exit(1);
    cli.options = kernel_options;
    for (cli.positionals) |arg| {
        var iter = std.mem.splitScalar(u8, arg, ':');
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
                // "video:vnc:<width>:<height>:<ip>:<port>"

                const address_str = iter.next() orelse badKernelOption("video", "missing vnc address");
                const port_str = iter.next() orelse badKernelOption("video", "missing vnc port");

                const address = network.Address.parse(address_str) catch badKernelOption("video", "bad vnc endpoint");
                const port = std.fmt.parseInt(u16, port_str, 10) catch badKernelOption("video", "bad vnc endpoint");

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
                    badKernelOption("sdl", "sdl video output disabled!");
                }
            } else if (std.mem.eql(u8, device_type, "drm")) {
                badKernelOption("video", "drm not supported yet!");
            } else if (std.mem.eql(u8, device_type, "wayland")) {
                // "video:wayland:<width>:<height>"

                const display = Wayland_Display.init(
                    global_memory,
                    video_out_index,
                    res_x,
                    res_y,
                ) catch |err| switch (err) {
                    error.NoWaylandSupport => {
                        @panic("Could not find Wayland socket!");
                    },
                    else => |e| return e,
                };

                ashet.drivers.install(&display.screen.driver);

                const thread = try ashet.scheduler.Thread.spawn(Wayland_Display.process_events_wrapper, display, .{
                    .stack_size = 1024 * 1024,
                });
                try thread.setName("wayland.eventloop");
                try thread.start();
                thread.detach();

                any_wayland_output = true;
            } else if (std.mem.eql(u8, device_type, "dummy")) {
                if (res_x != 320 or res_y != 240) badKernelOption("video", "resolution must be 320x240!");
                const driver = try global_memory.create(ashet.drivers.video.Virtual_Video_Output);
                driver.* = ashet.drivers.video.Virtual_Video_Output.init();
                ashet.drivers.install(&driver.driver);
            } else {
                badKernelOption("video", "bad video device type");
            }

            video_out_index += 1;
        } else {
            badKernelOption(component, "does not exist");
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

fn debug_write(msg: []const u8) void {
    std.debug.print("{s}", .{msg});
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

// extern const __machine_linmem_start: u8 align(4);
// extern const __machine_linmem_end: u8 align(4);

comptime {
    // Provide some global symbols.
    // We can fake the {flash,data,bss}_{start,end} symbols,
    // as we know that these won't overlap with linmem anyways:
    asm (
        \\
        \\.global __kernel_stack_start
        \\.global __kernel_stack_end
        \\__kernel_stack_start:
        \\.space 8 * 1024 * 1024        # 8 MB of stack
        \\__kernel_stack_end:
        \\
        \\.align 4096
        \\__kernel_flash_start:
        \\__kernel_flash_end:
        \\__kernel_data_start:
        \\__kernel_data_end:
        \\__kernel_bss_start:
        \\__kernel_bss_end:
    );
}

var linear_memory: [64 * 1024 * 1024]u8 align(4096) = undefined;

pub fn get_linear_memory_region() ashet.memory.Range {
    return .{
        .base = @intFromPtr(&linear_memory),
        .length = linear_memory.len,
    };
}
