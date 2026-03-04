const std = @import("std");
const ashet = @import("../../../../main.zig");
const rv32 = ashet.ports.platforms.riscv;
const logger = std.log.scoped(.@"qemu-ashet-base");

pub const peripherals = @import("peripherals.zig");

pub const machine_config = ashet.ports.MachineConfig{
    .load_sections = .{ .data = true, .bss = true },
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
};

fn get_tick_count_ms() u64 { // return value in ms
    return 0;
}

fn initialize() !void {
    // TODO: Setup machine
}

fn debug_write(msg: []const u8) void {
    for (msg) |c| {
        peripherals.debug_output.tx.* = c;
    }
}

extern const __kernel_ram_start: u8 align(4); // pointer to the first byte of RAM
extern const __machine_linmem_start: u8 align(4); // pointer to the first byte of RAM after all kernel data

fn get_linear_memory_region() ashet.memory.Range {
    const ram_start = @intFromPtr(&__kernel_ram_start);

    const linmem_start = @intFromPtr(&__machine_linmem_start);
    const linmem_end = ram_start + peripherals.system_info.ram_size.*;

    return .{ .base = linmem_start, .length = linmem_end - linmem_start };
}
