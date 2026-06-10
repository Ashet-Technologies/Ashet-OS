const std = @import("std");
const ashet = @import("../../../../main.zig");
const ppc = ashet.ports.platforms.ppc;
const logger = std.log.scoped(.@"nintendo-gc");

pub const machine_config = ashet.ports.MachineConfig{
    .load_sections = .{ .data = false, .bss = false },
    .memory_protection = null,
    .initialize = initialize,
    .early_initialize = null,
    .debug_write = debug_write,
    .get_linear_memory_region = get_linear_memory_region,
    .get_tick_count_ms = get_tick_count_ms,
    .halt = null,
};

const hw = struct {
    //! list of fixed hardware components

    var rtc: ashet.drivers.rtc.Dummy_RTC = undefined;
};

fn get_tick_count_ms() u64 { // return value in ms
    return 0; // TODO
}

fn initialize() !void {
    // TODO: Setup machine

    hw.rtc = .init(1778338669 * std.time.ns_per_s);

    // Finally install all drivers:
    ashet.drivers.install(&hw.rtc.driver);
}

noinline fn debug_write(msg: []const u8) void {
    for (msg) |c| {
        _ = c; //TODO
    }
}

extern const __machine_linmem_start: anyopaque align(4);
extern const __machine_linmem_length: anyopaque align(4);

fn get_linear_memory_region() ashet.memory.Range {
    return .{
        .base = @intFromPtr(&__machine_linmem_start),
        .length = @intFromPtr(&__machine_linmem_length),
    };
}
