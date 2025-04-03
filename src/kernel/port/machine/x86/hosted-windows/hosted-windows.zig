//!
//! Hosted Linux PC
//!

const std = @import("std");
const ashet = @import("../../../../main.zig");
const network = @import("network");
const args_parser = @import("args");
const logger = std.log.scoped(.@"hosted-windows");

pub const machine_config = ashet.ports.MachineConfig{
    .load_sections = .{ .data = false, .bss = false },
    .memory_protection = null,
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
    try network.init();

    startup_time = try std.time.Instant.now();
    logger.debug("startup time = {?}", .{startup_time});

    ashet.drivers.install(&hw.systemClock.driver);
}

fn debug_write(msg: []const u8) void {
    std.debug.print("{s}", .{msg});
}

comptime {
    // Provide some global symbols.
    // We can fake the {flash,data,bss}_{start,end} symbols,
    // as we know that these won't overlap with linmem anyways:
    asm (
    // Freakin' Windows linking.
    // On Windows, symbols are prefixed with an additional "_"!
        \\
        \\.global ___kernel_stack_start
        \\.global ___kernel_stack_end
        \\___kernel_stack_start:
        \\.space 8 * 1024 * 1024        # 8 MB of stack
        \\___kernel_stack_end:
        \\
        \\.align 4096
        \\.global ___kernel_flash_start
        \\.global ___kernel_flash_end
        \\.global ___kernel_data_start
        \\.global ___kernel_data_end
        \\.global ___kernel_bss_start
        \\.global ___kernel_bss_end
        \\___kernel_flash_start:
        \\___kernel_flash_end:
        \\___kernel_data_start:
        \\___kernel_data_end:
        \\___kernel_bss_start:
        \\___kernel_bss_end:
    );
}

var linear_memory: [64 * 1024 * 1024]u8 align(4096) = undefined;

pub fn get_linear_memory_region() ashet.memory.Range {
    return .{
        .base = @intFromPtr(&linear_memory),
        .length = linear_memory.len,
    };
}
