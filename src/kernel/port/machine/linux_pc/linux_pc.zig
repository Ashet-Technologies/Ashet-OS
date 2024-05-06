//!
//! Hosted Linux PC
//!

const std = @import("std");
const ashet = @import("../../../main.zig");
const network = @import("network");
const args_parser = @import("args");
const logger = std.log.scoped(.linux_pc);

const VNC_Server = @import("VNC_Server.zig");

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
pub const global_memory = global_memory_arena.allocator();

pub fn initialize() !void {
    const res = std.os.linux.mprotect(
        &linear_memory,
        linear_memory.len,
        std.os.linux.PROT.EXEC | std.os.linux.PROT.READ | std.os.linux.PROT.WRITE,
    );
    if (res != 0) @panic("mprotect failed!");

    try network.init();

    startup_time = try std.time.Instant.now();

    ashet.drivers.install(&hw.systemClock.driver);

    var cli = args_parser.parseForCurrentProcess(KernelOptions, global_memory, .print) catch std.os.exit(1);
    cli.options = kernel_options;
    for (cli.positionals) |arg| {
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
                    global_memory,
                    .{ .address = address, .port = port },
                    res_x,
                    res_y,
                );

                // TODO: This has to be solved differently
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