//!
//! Hosted Linux PC
//!

const std = @import("std");
const ashet = @import("../../../main.zig");
const x86 = @import("platform");
const logger = std.log.scoped(.linux_pc);

const args = @import("args");

pub const machine_config = ashet.ports.MachineConfig{
    .load_sections = .{ .data = false, .bss = false },
};

const hw = struct {
    //! list of fixed hardware components

    var video0: ashet.drivers.video.Virtual_Video_Output = .{};
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

pub fn initialize() !void {
    startup_time = try std.time.Instant.now();

    ashet.drivers.install(&hw.video0.driver);
    ashet.drivers.install(&hw.systemClock.driver);
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
        \\.space 8192 * 4
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
